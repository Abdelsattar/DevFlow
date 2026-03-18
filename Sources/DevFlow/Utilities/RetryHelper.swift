import Foundation

// MARK: - Retry Configuration

/// Configuration for retry behavior.
struct RetryConfiguration: Sendable {
    /// Maximum number of attempts (including the initial one).
    let maxAttempts: Int

    /// Base delay between retries (doubled each attempt for exponential backoff).
    let baseDelay: TimeInterval

    /// Maximum delay cap to prevent excessively long waits.
    let maxDelay: TimeInterval

    /// HTTP status codes that should trigger a retry.
    let retryableStatusCodes: Set<Int>

    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        retryableStatusCodes: [429, 502, 503, 504]
    )
}

// MARK: - Retry Helper

/// Shared async retry utility with exponential backoff for transient HTTP errors.
enum RetryHelper {

    /// Execute an async throwing operation with automatic retries on transient failures.
    ///
    /// - Parameters:
    ///   - configuration: Retry configuration (defaults to `.default`).
    ///   - operation: The async operation to execute.
    /// - Returns: The result of the successful operation.
    /// - Throws: The last error if all attempts are exhausted.
    @discardableResult
    static func withRetry<T: Sendable>(
        configuration: RetryConfiguration = .default,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...configuration.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if we should retry
                guard attempt < configuration.maxAttempts,
                      shouldRetry(error: error, configuration: configuration) else {
                    throw error
                }

                // Exponential backoff: baseDelay * 2^(attempt-1), capped at maxDelay
                let delay = min(
                    configuration.baseDelay * pow(2.0, Double(attempt - 1)),
                    configuration.maxDelay
                )

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // Should never reach here, but just in case
        throw lastError ?? CancellationError()
    }

    /// Execute an async operation with a hard deadline, throwing `ChatSessionError.timeout` if it
    /// doesn't complete in time. Cancels the underlying work when the deadline fires.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to allow.
    ///   - operation: The async throwing work to run.
    /// - Returns: The result of `operation`.
    /// - Throws: `ChatSessionError.timeout` when the deadline is exceeded;
    ///           any error thrown by `operation` otherwise.
    static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ChatSessionError.timeout
            }
            // The first child to finish wins; cancel the other.
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Determine if an error is retryable based on the configuration.
    private static func shouldRetry(error: Error, configuration: RetryConfiguration) -> Bool {
        // Don't retry cancellation
        if error is CancellationError { return false }

        // Check for HTTP status codes in known service error types
        if let jiraError = error as? JiraServiceError {
            if case .httpError(let statusCode, _) = jiraError {
                return configuration.retryableStatusCodes.contains(statusCode)
            }
        }

        if let githubError = error as? GitHubServiceError {
            if case .httpError(let statusCode, _) = githubError {
                return configuration.retryableStatusCodes.contains(statusCode)
            }
        }

        if let copilotError = error as? CopilotServiceError {
            if case .httpError(let statusCode, _) = copilotError {
                return configuration.retryableStatusCodes.contains(statusCode)
            }
            // Retry gateway unreachable (transient network issue)
            if case .gatewayUnreachable = copilotError {
                return true
            }
        }

        // Don't retry auth errors — these require user action, not retries
        if error is CopilotAuthError { return false }
        if error is JiraOAuthError { return false }

        // Retry URLError for transient network issues
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost:
                return true
            default:
                return false
            }
        }

        return false
    }
}
