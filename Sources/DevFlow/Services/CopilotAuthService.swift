import Foundation

// MARK: - Copilot Auth Errors

enum CopilotAuthError: Error, LocalizedError {
    case deviceFlowFailed(String)
    case tokenExpired
    case authorizationPending
    case slowDown
    case userDenied
    case pollTimeout
    case copilotTokenFailed(String)
    case noGitHubToken
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .deviceFlowFailed(let detail):
            return "GitHub Device Flow failed: \(detail)"
        case .tokenExpired:
            return "Device code expired. Please try again."
        case .authorizationPending:
            return "Waiting for authorization..."
        case .slowDown:
            return "Rate limited. Slowing down..."
        case .userDenied:
            return "Authorization was denied."
        case .pollTimeout:
            return "Authorization timed out. Please try again."
        case .copilotTokenFailed(let detail):
            return "Failed to get Copilot token: \(detail)"
        case .noGitHubToken:
            return "No GitHub token. Please sign in first."
        case .notAuthenticated:
            return "Not authenticated with GitHub Copilot."
        }
    }
}

// MARK: - Device Code Response

struct DeviceCodeResponse: Codable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

// MARK: - GitHub OAuth Token

struct GitHubOAuthToken: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

// MARK: - Copilot Token

struct CopilotToken: Codable {
    let token: String
    let expiresAt: Int
    let endpoints: CopilotEndpoints?

    var isExpired: Bool {
        Date().timeIntervalSince1970 >= Double(expiresAt - 60)
    }

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case endpoints
    }
}

struct CopilotEndpoints: Codable {
    let api: String?
    let proxy: String?
}

// MARK: - Copilot Auth Service

/// Handles GitHub Copilot authentication using the GitHub Device Flow.
///
/// Flow:
/// 1. Request a device code from GitHub
/// 2. Show the user code and verification URL to the user
/// 3. User navigates to github.com/login/device and enters the code
/// 4. App polls GitHub until the user authorizes (or times out)
/// 5. App receives a GitHub OAuth token
/// 6. App exchanges the GitHub token for a Copilot-specific token
/// 7. Copilot token is used to call the Copilot API directly
///
/// This eliminates the need for the external `copilot-api` npm package.
@MainActor
final class CopilotAuthService {
    private let appState: AppState
    private let session: URLSession

    // GitHub OAuth App Client ID for Copilot (same as VS Code uses).
    // This is a PUBLIC client identifier — not a secret. It is the same value
    // embedded in VS Code's open-source Copilot extension. If you register your
    // own GitHub OAuth App, replace this value with your own client ID.
    private let copilotClientId = "Iv1.b507a08c87ecfe98"

    // GitHub endpoints
    private let deviceCodeURL = "https://github.com/login/device/code"
    private let tokenPollURL = "https://github.com/login/oauth/access_token"
    private let copilotTokenURL = "https://api.github.com/copilot_internal/v2/token"

    // Device flow state (published for UI binding)
    var deviceCode: DeviceCodeResponse?
    var isPolling: Bool = false
    var pollError: String?

    init(appState: AppState) {
        self.appState = appState
        self.session = URLSession.shared
    }

    // MARK: - Public API

    /// Step 1: Request a device code. Returns the device code response
    /// containing the user code the user must enter at github.com/login/device.
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        guard let url = URL(string: deviceCodeURL) else {
            throw CopilotAuthError.deviceFlowFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "client_id=\(copilotClientId)&scope=copilot"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CopilotAuthError.deviceFlowFailed(errorBody)
        }

        let deviceCodeResponse = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        self.deviceCode = deviceCodeResponse
        return deviceCodeResponse
    }

    /// Step 2: Poll for the user to complete authorization.
    /// Call this after requestDeviceCode(). It will poll until the user authorizes,
    /// denies, or the code expires.
    func pollForAuthorization(deviceCode: DeviceCodeResponse) async throws -> GitHubOAuthToken {
        isPolling = true
        pollError = nil
        defer { isPolling = false }

        var interval = TimeInterval(max(deviceCode.interval, 5))
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))

        while Date() < deadline {
            try Task.checkCancellation()

            // Wait the required interval
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

            do {
                let token = try await attemptTokenExchange(deviceCode: deviceCode.deviceCode)
                // Success! Save the GitHub token
                try saveGitHubToken(token)
                return token
            } catch CopilotAuthError.authorizationPending {
                // User hasn't authorized yet, keep polling
                continue
            } catch CopilotAuthError.slowDown {
                // Increase interval by 5 seconds
                interval += 5
                continue
            } catch CopilotAuthError.tokenExpired {
                throw CopilotAuthError.tokenExpired
            } catch CopilotAuthError.userDenied {
                throw CopilotAuthError.userDenied
            } catch {
                // For other errors, keep trying until deadline
                pollError = error.localizedDescription
                continue
            }
        }

        throw CopilotAuthError.pollTimeout
    }

    /// Step 3: Get a Copilot-specific token using the GitHub OAuth token.
    /// The Copilot token is short-lived (~30 min) and must be refreshed.
    func getCopilotToken() async throws -> CopilotToken {
        // Check if we have a cached, non-expired Copilot token
        if let cached = loadCopilotToken(), !cached.isExpired {
            return cached
        }

        // Get the GitHub OAuth token
        guard let githubToken = loadGitHubToken() else {
            throw CopilotAuthError.noGitHubToken
        }

        // Exchange for a Copilot token
        guard let url = URL(string: copilotTokenURL) else {
            throw CopilotAuthError.copilotTokenFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(githubToken.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitHubCopilotChat/0.22.4", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue("vscode/1.95.3", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotAuthError.copilotTokenFailed("No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                // GitHub token may be revoked
                throw CopilotAuthError.noGitHubToken
            }
            throw CopilotAuthError.copilotTokenFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let copilotToken = try JSONDecoder().decode(CopilotToken.self, from: data)
        try saveCopilotToken(copilotToken)
        return copilotToken
    }

    /// Check if the user is authenticated.
    var isAuthenticated: Bool {
        loadGitHubToken() != nil
    }

    /// Sign out: remove all tokens.
    func signOut() {
        try? appState.keychainService.delete(
            service: KeychainService.copilotGitHubService,
            account: "github_oauth_token"
        )
        try? appState.keychainService.delete(
            service: KeychainService.copilotTokenService,
            account: "copilot_token"
        )
        deviceCode = nil
    }

    // MARK: - Token Exchange (Polling)

    private func attemptTokenExchange(deviceCode: String) async throws -> GitHubOAuthToken {
        guard let url = URL(string: tokenPollURL) else {
            throw CopilotAuthError.deviceFlowFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "client_id=\(copilotClientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CopilotAuthError.deviceFlowFailed(errorBody)
        }

        // Parse the response - GitHub returns error as a field, not as HTTP status
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorCode = json["error"] as? String {
            switch errorCode {
            case "authorization_pending":
                throw CopilotAuthError.authorizationPending
            case "slow_down":
                throw CopilotAuthError.slowDown
            case "expired_token":
                throw CopilotAuthError.tokenExpired
            case "access_denied":
                throw CopilotAuthError.userDenied
            default:
                let description = json["error_description"] as? String ?? errorCode
                throw CopilotAuthError.deviceFlowFailed(description)
            }
        }

        return try JSONDecoder().decode(GitHubOAuthToken.self, from: data)
    }

    // MARK: - Token Persistence

    private func saveGitHubToken(_ token: GitHubOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        try appState.keychainService.saveOrUpdate(
            service: KeychainService.copilotGitHubService,
            account: "github_oauth_token",
            token: jsonString
        )
    }

    func loadGitHubToken() -> GitHubOAuthToken? {
        guard let jsonString = try? appState.keychainService.retrieve(
            service: KeychainService.copilotGitHubService,
            account: "github_oauth_token"
        ),
        let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(GitHubOAuthToken.self, from: data)
    }

    private func saveCopilotToken(_ token: CopilotToken) throws {
        let data = try JSONEncoder().encode(token)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        try appState.keychainService.saveOrUpdate(
            service: KeychainService.copilotTokenService,
            account: "copilot_token",
            token: jsonString
        )
    }

    private func loadCopilotToken() -> CopilotToken? {
        guard let jsonString = try? appState.keychainService.retrieve(
            service: KeychainService.copilotTokenService,
            account: "copilot_token"
        ),
        let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CopilotToken.self, from: data)
    }
}
