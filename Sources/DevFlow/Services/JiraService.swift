import Foundation

// MARK: - JIRA Service Errors

enum JiraServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL(String)
    case authenticationFailed
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "JIRA is not configured. Please complete setup."
        case .invalidURL(let url):
            return "Invalid JIRA URL: \(url)"
        case .authenticationFailed:
            return "JIRA authentication failed. Check your email and API token."
        case .httpError(let code, let message):
            return "JIRA API error (\(code)): \(message)"
        case .decodingError(let detail):
            return "Failed to parse JIRA response: \(detail)"
        case .noToken:
            return "No JIRA API token found. Please add it in Settings."
        }
    }
}

// MARK: - JIRA Service

/// Async client for JIRA Cloud REST API v3.
/// Handles authentication, ticket search, component fetching, and ticket detail retrieval.
@MainActor
final class JiraService {
    private let appState: AppState
    private let session: URLSession
    private let decoder: JSONDecoder

    init(appState: AppState) {
        self.appState = appState
        self.session = URLSession.shared

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Auth Header

    private func authHeader() async throws -> String {
        switch appState.jiraAuthMethod {
        case .oauth:
            // Use OAuth 2.0 Bearer token (auto-refreshes if expired)
            let accessToken = try await appState.jiraOAuthService.getValidAccessToken()
            return "Bearer \(accessToken)"
        case .basicAuth:
            // Legacy Basic Auth with email + API token
            let token: String
            do {
                token = try appState.keychainService.retrieve(
                    service: KeychainService.jiraService,
                    account: appState.jiraEmail
                )
            } catch KeychainError.itemNotFound {
                throw JiraServiceError.noToken
            }

            let credentials = "\(appState.jiraEmail):\(token)"
            guard let data = credentials.data(using: .utf8) else {
                throw JiraServiceError.noToken
            }
            return "Basic \(data.base64EncodedString())"
        }
    }

    private func buildRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        // For OAuth, use the cloud API base URL with the cloud ID
        let baseURL: String
        if appState.jiraAuthMethod == .oauth && !appState.jiraCloudId.isEmpty {
            baseURL = "https://api.atlassian.com/ex/jira/\(appState.jiraCloudId)"
        } else {
            baseURL = appState.jiraBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw JiraServiceError.invalidURL("\(baseURL)\(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await authHeader(), forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    // MARK: - Test Connection

    /// Validates that the JIRA credentials work by fetching the current user.
    func testConnection() async throws -> Bool {
        let request = try await buildRequest(path: "/rest/api/3/myself")
        let urlSession = session
        return try await RetryHelper.withRetry {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            switch httpResponse.statusCode {
            case 200:
                return true
            case 401, 403:
                throw JiraServiceError.authenticationFailed
            default:
                throw JiraServiceError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: "Unexpected response"
                )
            }
        }
    }

    // MARK: - Fetch Projects

    /// Fetch all JIRA projects accessible to the authenticated user, paginating through all pages.
    func fetchProjects() async throws -> [JiraProject] {
        var allProjects: [JiraProject] = []
        var startAt = 0
        let maxResults = 50
        let urlSession = session
        let jsonDecoder = decoder

        struct ProjectPage: Decodable {
            let values: [JiraProject]
            let isLast: Bool
        }

        while true {
            let request = try await buildRequest(
                path: "/rest/api/3/project/search?startAt=\(startAt)&maxResults=\(maxResults)&orderBy=name"
            )
            let page: ProjectPage = try await RetryHelper.withRetry {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
                }
                switch httpResponse.statusCode {
                case 200:
                    do {
                        return try jsonDecoder.decode(ProjectPage.self, from: data)
                    } catch {
                        throw JiraServiceError.decodingError(error.localizedDescription)
                    }
                case 401, 403:
                    throw JiraServiceError.authenticationFailed
                default:
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
                }
            }
            allProjects.append(contentsOf: page.values)
            if page.isLast || page.values.isEmpty {
                break
            }
            startAt += maxResults
        }

        return allProjects
    }

    // MARK: - Fetch Tickets

    /// Search JIRA tickets in the given project, paginating through all results.
    /// By default fetches all non-done tickets in the scope (not limited to current user).
    func fetchTickets(
        project: String,
        scope: TicketScope = .currentSprint,
        assigneeFilter: AssigneeFilter = .all
    ) async throws -> [JiraTicket] {
        let jql = Self.makeTicketJQL(
            project: project,
            scope: scope,
            assigneeFilter: assigneeFilter
        )

        let pageSize = 100
        var allTickets: [JiraTicket] = []
        var nextPageToken: String?
        let urlSession = session
        let jsonDecoder = decoder

        // Paginate through all results
        repeat {
            var bodyDict: [String: Any] = [
                "jql": jql,
                "maxResults": pageSize,
                "fields": [
                    "summary", "description", "status", "priority",
                    "assignee", "components", "comment", "issuetype"
                ]
            ]

            if let token = nextPageToken {
                bodyDict["nextPageToken"] = token
            }

            let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)
            let request = try await buildRequest(path: "/rest/api/3/search/jql", method: "POST", body: bodyData)

            let searchResponse: JiraSearchResponse = try await RetryHelper.withRetry {
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
                }

                switch httpResponse.statusCode {
                case 200:
                    do {
                        return try jsonDecoder.decode(JiraSearchResponse.self, from: data)
                    } catch {
                        throw JiraServiceError.decodingError(error.localizedDescription)
                    }
                case 401, 403:
                    throw JiraServiceError.authenticationFailed
                default:
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
                }
            }

            allTickets.append(contentsOf: searchResponse.issues)

            // Stop if this is the last page or no more tokens
            if searchResponse.isLast == true || searchResponse.nextPageToken == nil {
                break
            }
            nextPageToken = searchResponse.nextPageToken
        } while true

        return allTickets
    }

    nonisolated static func makeTicketJQL(
        project: String,
        scope: TicketScope,
        assigneeFilter: AssigneeFilter = .all
    ) -> String {
        var jqlParts = [
            "project = \(project)",
            "status != Done"
        ]

        switch assigneeFilter {
        case .currentUser:
            jqlParts.append("assignee = currentUser()")
        case .all:
            break
        }

        if let scopeClause = scope.jqlClause {
            jqlParts.append(scopeClause)
        }

        return jqlParts.joined(separator: " AND ") + " ORDER BY updated DESC"
    }

    // MARK: - Fetch Components

    /// Fetch all components for a given JIRA project.
    func fetchComponents(project: String) async throws -> [JiraComponent] {
        let request = try await buildRequest(path: "/rest/api/3/project/\(project)/components")
        let urlSession = session
        let jsonDecoder = decoder
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    return try jsonDecoder.decode([JiraComponent].self, from: data)
                } catch {
                    throw JiraServiceError.decodingError(error.localizedDescription)
                }
            case 401, 403:
                throw JiraServiceError.authenticationFailed
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    // MARK: - Transitions

    /// Fetch available transitions for a ticket.
    func fetchTransitions(key: String) async throws -> [JiraTransition] {
        let request = try await buildRequest(path: "/rest/api/3/issue/\(key)/transitions")
        let urlSession = session
        let jsonDecoder = decoder
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    let container = try jsonDecoder.decode(JiraTransitionContainer.self, from: data)
                    return container.transitions
                } catch {
                    throw JiraServiceError.decodingError(error.localizedDescription)
                }
            case 401, 403:
                throw JiraServiceError.authenticationFailed
            case 404:
                throw JiraServiceError.httpError(statusCode: 404, message: "Ticket \(key) not found")
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    /// Transition a ticket to a new status by status name.
    /// Finds the matching transition ID automatically.
    func transitionTicket(key: String, statusName: String) async throws {
        let transitions = try await fetchTransitions(key: key)
        guard let transition = transitions.first(where: {
            $0.name.lowercased() == statusName.lowercased() ||
            $0.to.name.lowercased() == statusName.lowercased()
        }) else {
            let available = transitions.map(\.name).joined(separator: ", ")
            throw JiraServiceError.httpError(
                statusCode: 0,
                message: "No transition to '\(statusName)' found. Available: \(available)"
            )
        }

        let bodyDict: [String: Any] = [
            "transition": ["id": transition.id]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)
        let request = try await buildRequest(
            path: "/rest/api/3/issue/\(key)/transitions",
            method: "POST",
            body: bodyData
        )

        let urlSession = session
        try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            // 204 No Content is the success response for transitions
            switch httpResponse.statusCode {
            case 200...204:
                return
            case 401, 403:
                throw JiraServiceError.authenticationFailed
            case 404:
                throw JiraServiceError.httpError(statusCode: 404, message: "Ticket \(key) not found")
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    // MARK: - Comments

    /// Add a plain-text comment to a ticket.
    /// The body is sent as ADF (Atlassian Document Format) with a single paragraph.
    func addComment(key: String, body: String) async throws {
        let adfBody: [String: Any] = [
            "body": [
                "version": 1,
                "type": "doc",
                "content": [
                    [
                        "type": "paragraph",
                        "content": [
                            [
                                "type": "text",
                                "text": body
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: adfBody)
        let request = try await buildRequest(
            path: "/rest/api/3/issue/\(key)/comment",
            method: "POST",
            body: bodyData
        )

        let urlSession = session
        try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            switch httpResponse.statusCode {
            case 200, 201:
                return
            case 401, 403:
                throw JiraServiceError.authenticationFailed
            case 404:
                throw JiraServiceError.httpError(statusCode: 404, message: "Ticket \(key) not found")
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    // MARK: - Fetch Ticket Detail

    /// Fetch full ticket detail including all comments.
    func fetchTicketDetail(key: String) async throws -> JiraTicket {
        let fields = [
            "summary", "description", "status", "priority",
            "assignee", "components", "comment", "issuetype"
        ].joined(separator: ",")

        let request = try await buildRequest(path: "/rest/api/3/issue/\(key)?fields=\(fields)")
        let urlSession = session
        let jsonDecoder = decoder
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JiraServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    return try jsonDecoder.decode(JiraTicket.self, from: data)
                } catch {
                    throw JiraServiceError.decodingError(error.localizedDescription)
                }
            case 401, 403:
                throw JiraServiceError.authenticationFailed
            case 404:
                throw JiraServiceError.httpError(statusCode: 404, message: "Ticket \(key) not found")
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JiraServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }
}
