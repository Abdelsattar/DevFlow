import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Jira OAuth Errors

enum JiraOAuthError: Error, LocalizedError {
    case notConfigured
    case authenticationCancelled
    case invalidResponse
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case noRefreshToken
    case invalidCallbackURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Jira OAuth is not configured. Set your Client ID in Settings."
        case .authenticationCancelled:
            return "Authentication was cancelled."
        case .invalidResponse:
            return "Invalid response from Atlassian."
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        case .tokenRefreshFailed(let detail):
            return "Token refresh failed: \(detail)"
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        case .invalidCallbackURL:
            return "Invalid callback URL from Atlassian."
        }
    }
}

// MARK: - Jira OAuth Token

struct JiraOAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String
    let scope: String?
    let createdAt: Date

    var isExpired: Bool {
        guard let expiresIn else { return false }
        return Date().timeIntervalSince(createdAt) >= Double(expiresIn - 60)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
        case createdAt
    }
}

// MARK: - Jira Accessible Resource

struct JiraAccessibleResource: Codable {
    let id: String
    let url: String
    let name: String
    let scopes: [String]
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, url, name, scopes
        case avatarUrl = "avatarUrl"
    }
}

// MARK: - Jira OAuth Service

/// Handles Atlassian/Jira OAuth 2.0 (3LO) authentication with PKCE.
///
/// Flow:
/// 1. User clicks "Sign in with Atlassian"
/// 2. ASWebAuthenticationSession opens the Atlassian consent page
/// 3. User authorizes, Atlassian redirects back with an authorization code
/// 4. App exchanges code for access + refresh tokens
/// 5. App fetches accessible resources to get the cloud ID
/// 6. Tokens are stored in Keychain, cloud ID in UserDefaults
///
/// Token refresh is automatic and transparent to callers.
@MainActor
final class JiraOAuthService: NSObject {
    private let appState: AppState
    private let session: URLSession

    // Atlassian OAuth 2.0 endpoints
    private let authorizeURL = "https://auth.atlassian.com/authorize"
    private let tokenURL = "https://auth.atlassian.com/oauth/token"
    private let accessibleResourcesURL = "https://api.atlassian.com/oauth/token/accessible-resources"

    // PKCE state
    private var codeVerifier: String?

    // The custom URL scheme for the callback
    private let callbackScheme = "devflow"
    private let callbackPath = "oauth/callback/jira"

    // Required scopes for Jira Cloud
    private let scopes = [
        "read:jira-work",
        "write:jira-work",
        "read:jira-user",
        "offline_access"
    ]

    init(appState: AppState) {
        self.appState = appState
        self.session = URLSession.shared
    }

    // MARK: - Public API

    /// Start the OAuth 2.0 authorization flow.
    /// Opens the system browser for Atlassian consent, then exchanges the code for tokens.
    func authenticate() async throws {
        let clientId = appState.jiraOAuthClientId
        guard !clientId.isEmpty else {
            throw JiraOAuthError.notConfigured
        }

        // Generate PKCE code verifier and challenge
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        self.codeVerifier = verifier

        // Build authorization URL
        let redirectURI = "\(callbackScheme)://\(callbackPath)"
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "audience", value: "api.atlassian.com"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else {
            throw JiraOAuthError.notConfigured
        }

        // Present the authentication session
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: JiraOAuthError.authenticationCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let url else {
                    continuation.resume(throwing: JiraOAuthError.invalidCallbackURL)
                    return
                }
                continuation.resume(returning: url)
            }

            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            authSession.start()
        }

        // Extract the authorization code from the callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw JiraOAuthError.invalidCallbackURL
        }

        // Exchange authorization code for tokens
        let token = try await exchangeCodeForToken(code: code, redirectURI: redirectURI)

        // Save the token
        try saveToken(token)

        // Fetch accessible resources to get the cloud ID and site URL
        try await fetchAndSaveAccessibleResources(accessToken: token.accessToken)
    }

    /// Get a valid access token, refreshing if needed.
    /// Returns the bearer token string ready for use in Authorization headers.
    func getValidAccessToken() async throws -> String {
        guard let token = loadToken() else {
            throw JiraOAuthError.notConfigured
        }

        if token.isExpired {
            let refreshed = try await refreshAccessToken(token)
            try saveToken(refreshed)
            return refreshed.accessToken
        }

        return token.accessToken
    }

    /// Check if the user is authenticated with OAuth.
    var isAuthenticated: Bool {
        loadToken() != nil && !appState.jiraCloudId.isEmpty
    }

    /// Sign out: remove tokens from Keychain and clear cloud ID.
    func signOut() {
        try? appState.keychainService.delete(
            service: KeychainService.jiraOAuthService,
            account: "oauth_token"
        )
        appState.jiraCloudId = ""
        appState.jiraCloudName = ""
        appState.jiraAuthMethod = .basicAuth
    }

    // MARK: - Token Exchange

    private func exchangeCodeForToken(code: String, redirectURI: String) async throws -> JiraOAuthToken {
        guard let url = URL(string: tokenURL) else {
            throw JiraOAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": appState.jiraOAuthClientId,
            "code": code,
            "redirect_uri": redirectURI,
        ]

        if let verifier = codeVerifier {
            body["code_verifier"] = verifier
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JiraOAuthError.tokenExchangeFailed(errorBody)
        }

        // Parse the token response, injecting createdAt
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        json["createdAt"] = Date().timeIntervalSinceReferenceDate

        let tokenData = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let interval = try container.decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return try decoder.decode(JiraOAuthToken.self, from: tokenData)
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(_ token: JiraOAuthToken) async throws -> JiraOAuthToken {
        guard let refreshToken = token.refreshToken else {
            throw JiraOAuthError.noRefreshToken
        }

        guard let url = URL(string: tokenURL) else {
            throw JiraOAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": appState.jiraOAuthClientId,
            "refresh_token": refreshToken,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JiraOAuthError.tokenRefreshFailed(errorBody)
        }

        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        json["createdAt"] = Date().timeIntervalSinceReferenceDate
        // Preserve the refresh token if the response doesn't include a new one
        if json["refresh_token"] == nil {
            json["refresh_token"] = refreshToken
        }

        let tokenData = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let interval = try container.decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return try decoder.decode(JiraOAuthToken.self, from: tokenData)
    }

    // MARK: - Accessible Resources

    private func fetchAndSaveAccessibleResources(accessToken: String) async throws {
        guard let url = URL(string: accessibleResourcesURL) else {
            throw JiraOAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw JiraOAuthError.invalidResponse
        }

        let resources = try JSONDecoder().decode([JiraAccessibleResource].self, from: data)

        // Use the first accessible resource (most users have one Jira site)
        guard let resource = resources.first else {
            throw JiraOAuthError.invalidResponse
        }

        appState.jiraCloudId = resource.id
        appState.jiraCloudName = resource.name
        appState.jiraBaseURL = resource.url
        appState.jiraAuthMethod = .oauth
    }

    // MARK: - Token Persistence

    private func saveToken(_ token: JiraOAuthToken) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        let data = try encoder.encode(token)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        try appState.keychainService.saveOrUpdate(
            service: KeychainService.jiraOAuthService,
            account: "oauth_token",
            token: jsonString
        )
    }

    private func loadToken() -> JiraOAuthToken? {
        guard let jsonString = try? appState.keychainService.retrieve(
            service: KeychainService.jiraOAuthService,
            account: "oauth_token"
        ),
        let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let interval = try container.decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return try? decoder.decode(JiraOAuthToken.self, from: data)
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .ascii) else { return verifier }
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension JiraOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
