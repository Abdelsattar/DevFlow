import Foundation

// MARK: - GitHub Service Errors

enum GitHubServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL(String)
    case authenticationFailed
    case httpError(statusCode: Int, message: String)
    case noToken
    case repositoryNotFound(String)
    case pullRequestCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GitHub is not configured. Please complete setup."
        case .invalidURL(let url):
            return "Invalid GitHub URL: \(url)"
        case .authenticationFailed:
            return "GitHub authentication failed. Check your Personal Access Token."
        case .httpError(let code, let message):
            return "GitHub API error (\(code)): \(message)"
        case .noToken:
            return "No GitHub PAT found. Please add it in Settings."
        case .repositoryNotFound(let repo):
            return "Repository '\(repo)' not found on GitHub."
        case .pullRequestCreationFailed(let reason):
            return "Failed to create pull request: \(reason)"
        }
    }
}

// MARK: - GitHub Service

/// Client for GitHub Enterprise REST API v3.
/// Supports connection testing, user info, repository lookup, and pull request creation.
@MainActor
final class GitHubService {
    private let appState: AppState
    private let session: URLSession
    private let decoder: JSONDecoder

    init(appState: AppState) {
        self.appState = appState
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
    }

    // MARK: - Auth Header

    private func authHeader() throws -> String {
        let token: String
        do {
            token = try appState.keychainService.retrieve(
                service: KeychainService.githubService,
                account: appState.githubHost
            )
        } catch KeychainError.itemNotFound {
            throw GitHubServiceError.noToken
        }
        return "Bearer \(token)"
    }

    private func buildRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let host = appState.githubHost.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "https://\(host)/api/v3\(path)") else {
            throw GitHubServiceError.invalidURL("https://\(host)/api/v3\(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try authHeader(), forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    // MARK: - Test Connection

    /// Validates GitHub Enterprise credentials by fetching the authenticated user.
    func testConnection() async throws -> Bool {
        let request = try buildRequest(path: "/user")
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
                throw GitHubServiceError.authenticationFailed
            default:
                throw GitHubServiceError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: "Unexpected response"
                )
            }
        }
    }

    // MARK: - Current User

    /// Fetch the currently authenticated GitHub user.
    func getCurrentUser() async throws -> GitHubUser {
        let request = try buildRequest(path: "/user")
        let urlSession = session
        let jsonDecoder = decoder
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)
            try self.validateResponse(response, data: data)
            return try jsonDecoder.decode(GitHubUser.self, from: data)
        }
    }

    /// Fetch all organizations the authenticated user belongs to, paginating through all pages.
    func getUserOrganizations() async throws -> [GitHubOrganization] {
        var allOrgs: [GitHubOrganization] = []
        var page = 1
        let perPage = 100
        let urlSession = session
        let jsonDecoder = decoder

        while true {
            let request = try buildRequest(path: "/user/orgs?per_page=\(perPage)&page=\(page)")
            let pageOrgs: [GitHubOrganization] = try await RetryHelper.withRetry {
                let (data, response) = try await urlSession.data(for: request)
                try self.validateResponse(response, data: data)
                return try jsonDecoder.decode([GitHubOrganization].self, from: data)
            }
            allOrgs.append(contentsOf: pageOrgs)
            if pageOrgs.count < perPage {
                break
            }
            page += 1
        }

        return allOrgs.sorted { $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending }
    }

    /// Validates the token and returns the authenticated user info and organizations.
    /// Used during setup to auto-detect the user's identity after pasting a token.
    func validateTokenAndGetInfo() async throws -> (user: GitHubUser, organizations: [GitHubOrganization]) {
        let user = try await getCurrentUser()
        let orgs = try await getUserOrganizations()
        return (user, orgs)
    }

    // MARK: - Repository

    /// Fetch a repository by owner and name.
    func getRepository(owner: String, name: String) async throws -> GitHubRepository {
        let request = try buildRequest(path: "/repos/\(owner)/\(name)")
        let urlSession = session
        let jsonDecoder = decoder
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            if httpResponse.statusCode == 404 {
                throw GitHubServiceError.repositoryNotFound("\(owner)/\(name)")
            }

            try self.validateResponse(response, data: data)
            return try jsonDecoder.decode(GitHubRepository.self, from: data)
        }
    }

    /// Parse a git remote URL to extract owner and repo name.
    /// Handles both SSH (git@host:owner/repo.git) and HTTPS (https://host/owner/repo.git) formats.
    nonisolated static func parseRemoteURL(_ url: String) -> (owner: String, name: String)? {
        // SSH format: git@github.your-company.com:owner/repo.git
        if url.contains("@") && url.contains(":") {
            let afterColon = url.split(separator: ":").last.map(String.init) ?? ""
            let cleaned = afterColon.replacingOccurrences(of: ".git", with: "")
            let parts = cleaned.split(separator: "/")
            if parts.count >= 2 {
                return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
            }
        }

        // HTTPS format: https://github.your-company.com/owner/repo.git
        if let urlObj = URL(string: url) {
            let pathComponents = urlObj.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 {
                let name = pathComponents.last?.replacingOccurrences(of: ".git", with: "") ?? ""
                let owner = pathComponents[pathComponents.count - 2]
                return (owner, name)
            }
        }

        return nil
    }

    // MARK: - Pull Request

    /// Create a pull request on the repository.
    func createPullRequest(
        owner: String,
        repo: String,
        title: String,
        body: String,
        head: String,
        base: String
    ) async throws -> GitHubPullRequest {
        let prBody = CreatePullRequestBody(
            title: title,
            body: body,
            head: head,
            base: base
        )

        let bodyData = try JSONEncoder().encode(prBody)
        let request = try buildRequest(
            path: "/repos/\(owner)/\(repo)/pulls",
            method: "POST",
            body: bodyData
        )

        let urlSession = session
        let jsonDecoder = decoder
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubServiceError.httpError(statusCode: 0, message: "No HTTP response")
            }

            switch httpResponse.statusCode {
            case 201:
                return try jsonDecoder.decode(GitHubPullRequest.self, from: data)
            case 422:
                // Validation failed — e.g. PR already exists for this head branch
                let errorBody = String(data: data, encoding: .utf8) ?? "Validation error"
                throw GitHubServiceError.pullRequestCreationFailed(errorBody)
            case 401, 403:
                throw GitHubServiceError.authenticationFailed
            case 404:
                throw GitHubServiceError.repositoryNotFound("\(owner)/\(repo)")
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GitHubServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    /// Generate a PR body with a JIRA ticket link and summary.
    /// - Parameter jiraBaseURL: The user-configured Jira base URL (e.g. "https://yourorg.atlassian.net").
    ///   When empty the Jira link section is omitted.
    nonisolated static func buildPRBody(
        ticketKey: String,
        summary: String,
        changeSummary: String = "",
        jiraBaseURL: String = ""
    ) -> String {
        var body = "## Summary\n\(ticketKey): \(summary)"

        let trimmedBase = jiraBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !trimmedBase.isEmpty {
            let jiraLink = "[\(ticketKey)](\(trimmedBase)/browse/\(ticketKey))"
            body += "\n\n## Jira\n\(jiraLink)"
        }

        if !changeSummary.isEmpty {
            body += "\n\n## Changes\n\(changeSummary)"
        }

        return body
    }

    // MARK: - Response Validation

    private nonisolated func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubServiceError.httpError(statusCode: 0, message: "No HTTP response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw GitHubServiceError.authenticationFailed
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
