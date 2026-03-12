import Foundation

// MARK: - Copilot Service Errors

enum CopilotServiceError: Error, LocalizedError {
    case notConfigured
    case notAuthenticated
    case gatewayUnreachable(String)
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Copilot is not configured."
        case .notAuthenticated:
            return "Not authenticated with GitHub Copilot. Please sign in."
        case .gatewayUnreachable(let url):
            return "Cannot reach Copilot at \(url)."
        case .httpError(let code, let message):
            return "Copilot error (\(code)): \(message)"
        }
    }
}

// MARK: - Copilot Service

/// Client for GitHub Copilot chat completions.
///
/// Supports two modes:
/// 1. **Direct API** (default): Authenticates via Device Flow OAuth, gets a Copilot token,
///    and calls the Copilot API directly. No external dependencies.
/// 2. **External Gateway** (legacy): Connects to a user-managed OpenAI-compatible gateway
///    (e.g. copilot-api npm package) at a configurable URL.
@MainActor
final class CopilotService {
    private let appState: AppState
    private let session: URLSession

    init(appState: AppState) {
        self.appState = appState
        self.session = URLSession.shared
    }

    // MARK: - Test Connection

    /// Tests that the Copilot API is reachable and the user is authenticated.
    func testConnection() async throws -> Bool {
        switch appState.copilotAuthMethod {
        case .oauthDeviceFlow:
            return try await testDirectConnection()
        case .externalGateway:
            return try await testGatewayConnection()
        }
    }

    private func testDirectConnection() async throws -> Bool {
        // Try to get a Copilot token - this validates the full auth chain
        _ = try await appState.copilotAuthService.getCopilotToken()
        return true
    }

    private func testGatewayConnection() async throws -> Bool {
        let gatewayURL = appState.copilotGatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !gatewayURL.isEmpty, let url = URL(string: "\(gatewayURL)/models") else {
            throw CopilotServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        let finalRequest = request
        let urlSession = session
        return try await RetryHelper.withRetry {
            do {
                let (_, response) = try await urlSession.data(for: finalRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    return false
                }

                switch httpResponse.statusCode {
                case 200:
                    return true
                default:
                    throw CopilotServiceError.httpError(
                        statusCode: httpResponse.statusCode,
                        message: "Unexpected response from gateway"
                    )
                }
            } catch is CopilotServiceError {
                throw CopilotServiceError.gatewayUnreachable(gatewayURL)
            } catch {
                throw CopilotServiceError.gatewayUnreachable(gatewayURL)
            }
        }
    }

    // MARK: - Streaming Chat Completions

    /// The model to use for chat completions.
    private var model: String {
        switch appState.copilotAuthMethod {
        case .oauthDeviceFlow:
            return "gpt-4o"
        case .externalGateway:
            return "gpt-4o"
        }
    }

    /// Stream a chat completion. Routes to the correct backend based on auth method.
    func streamChatCompletion(
        messages: [[String: String]],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        switch appState.copilotAuthMethod {
        case .oauthDeviceFlow:
            return try await streamDirectChatCompletion(
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .externalGateway:
            return try await streamGatewayChatCompletion(
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens
            )
        }
    }

    /// Non-streaming chat completion. Routes to the correct backend based on auth method.
    func chatCompletion(
        messages: [[String: String]],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) async throws -> String {
        switch appState.copilotAuthMethod {
        case .oauthDeviceFlow:
            return try await directChatCompletion(
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .externalGateway:
            return try await gatewayChatCompletion(
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens
            )
        }
    }

    // MARK: - Direct Copilot API (Authenticated)

    private func streamDirectChatCompletion(
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let copilotToken = try await appState.copilotAuthService.getCopilotToken()

        // Use the endpoint from the token, or fall back to default
        let baseURL = copilotToken.endpoints?.api ?? "https://api.githubcopilot.com"
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw CopilotServiceError.notConfigured
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": temperature
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(copilotToken.token)", forHTTPHeaderField: "Authorization")
        request.setValue("GitHubCopilotChat/0.22.4", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue("vscode/1.95.3", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("conversation-panel", forHTTPHeaderField: "Openai-Intent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotServiceError.gatewayUnreachable(baseURL)
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 1000 { break }
            }
            throw CopilotServiceError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorBody.isEmpty ? "Request failed" : errorBody
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            break
                        }

                        if let chunk = parseSSEChunk(payload) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func directChatCompletion(
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> String {
        let copilotToken = try await appState.copilotAuthService.getCopilotToken()

        let baseURL = copilotToken.endpoints?.api ?? "https://api.githubcopilot.com"
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw CopilotServiceError.notConfigured
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "temperature": temperature
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(copilotToken.token)", forHTTPHeaderField: "Authorization")
        request.setValue("GitHubCopilotChat/0.22.4", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue("vscode/1.95.3", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("conversation-panel", forHTTPHeaderField: "Openai-Intent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let finalRequest = request
        let urlSession = session
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: finalRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CopilotServiceError.gatewayUnreachable(baseURL)
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw CopilotServiceError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: errorBody
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw CopilotServiceError.httpError(
                    statusCode: 200,
                    message: "Unexpected response format"
                )
            }

            return content
        }
    }

    // MARK: - External Gateway (Legacy)

    private func streamGatewayChatCompletion(
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let gatewayURL = appState.copilotGatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !gatewayURL.isEmpty, let url = URL(string: "\(gatewayURL)/chat/completions") else {
            throw CopilotServiceError.notConfigured
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": temperature
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotServiceError.gatewayUnreachable(gatewayURL)
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 1000 { break }
            }
            throw CopilotServiceError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorBody.isEmpty ? "Request failed" : errorBody
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            break
                        }

                        if let chunk = parseSSEChunk(payload) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func gatewayChatCompletion(
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> String {
        let gatewayURL = appState.copilotGatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !gatewayURL.isEmpty, let url = URL(string: "\(gatewayURL)/chat/completions") else {
            throw CopilotServiceError.notConfigured
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "temperature": temperature
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let finalRequest = request
        let urlSession = session
        return try await RetryHelper.withRetry {
            let (data, response) = try await urlSession.data(for: finalRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CopilotServiceError.gatewayUnreachable(gatewayURL)
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw CopilotServiceError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: errorBody
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw CopilotServiceError.httpError(
                    statusCode: 200,
                    message: "Unexpected response format"
                )
            }

            return content
        }
    }

    // MARK: - SSE Parsing

    private func parseSSEChunk(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }
}
