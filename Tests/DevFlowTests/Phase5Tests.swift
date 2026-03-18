import Foundation
import Testing
@testable import DevFlow

// MARK: - Test Helper

/// Thread-safe counter for use in @Sendable closures during retry tests.
private final class CallCounter: @unchecked Sendable {
    private var _count = 0
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
        return _count
    }
}

// MARK: - RetryHelper Tests

@Suite("RetryHelper Tests")
struct RetryHelperTests {

    @Test("Succeeds on first attempt without retrying")
    func successOnFirstAttempt() async throws {
        let counter = CallCounter()
        let result = try await RetryHelper.withRetry {
            counter.increment()
            return "success"
        }
        #expect(result == "success")
        #expect(counter.count == 1)
    }

    @Test("Retries on transient error then succeeds")
    func retriesOnTransientError() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        let result: String = try await RetryHelper.withRetry(configuration: config) {
            let current = counter.increment()
            if current < 3 {
                throw JiraServiceError.httpError(statusCode: 503, message: "Service Unavailable")
            }
            return "recovered"
        }
        #expect(result == "recovered")
        #expect(counter.count == 3)
    }

    @Test("Does not retry non-retryable errors")
    func doesNotRetryNonRetryable() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        do {
            _ = try await RetryHelper.withRetry(configuration: config) {
                counter.increment()
                throw JiraServiceError.authenticationFailed
            } as String
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(counter.count == 1)
            #expect(error is JiraServiceError)
        }
    }

    @Test("Exhausts all attempts and throws last error")
    func exhaustsAllAttempts() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 2,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        do {
            _ = try await RetryHelper.withRetry(configuration: config) {
                counter.increment()
                throw JiraServiceError.httpError(statusCode: 502, message: "Bad Gateway")
            } as String
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(counter.count == 2)
            if let jiraError = error as? JiraServiceError,
               case .httpError(let code, _) = jiraError {
                #expect(code == 502)
            } else {
                Issue.record("Expected JiraServiceError.httpError")
            }
        }
    }

    @Test("Retries URLError for transient network issues")
    func retriesURLError() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        let result: String = try await RetryHelper.withRetry(configuration: config) {
            let current = counter.increment()
            if current < 2 {
                throw URLError(.timedOut)
            }
            return "recovered"
        }
        #expect(result == "recovered")
        #expect(counter.count == 2)
    }

    @Test("Retries CopilotServiceError.gatewayUnreachable")
    func retriesCopilotGatewayUnreachable() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        let result: String = try await RetryHelper.withRetry(configuration: config) {
            let current = counter.increment()
            if current < 2 {
                throw CopilotServiceError.gatewayUnreachable("http://localhost:3030")
            }
            return "connected"
        }
        #expect(result == "connected")
        #expect(counter.count == 2)
    }

    @Test("Does not retry CancellationError")
    func doesNotRetryCancellation() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        do {
            _ = try await RetryHelper.withRetry(configuration: config) {
                counter.increment()
                throw CancellationError()
            } as String
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(counter.count == 1)
            #expect(error is CancellationError)
        }
    }

    @Test("Retries GitHub httpError with retryable status codes")
    func retriesGitHubHttpError() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        let result: String = try await RetryHelper.withRetry(configuration: config) {
            let current = counter.increment()
            if current < 2 {
                throw GitHubServiceError.httpError(statusCode: 429, message: "Rate limited")
            }
            return "ok"
        }
        #expect(result == "ok")
        #expect(counter.count == 2)
    }

    @Test("withTimeout throws timeout error when operation exceeds deadline")
    func withTimeoutExpires() async throws {
        do {
            _ = try await RetryHelper.withTimeout(.milliseconds(50)) {
                // Simulate an operation that never finishes
                try await Task.sleep(for: .seconds(60))
                return "should not reach"
            }
            Issue.record("Expected ChatSessionError.timeout to be thrown")
        } catch let error as ChatSessionError {
            guard case .timeout = error else {
                Issue.record("Expected ChatSessionError.timeout, got \(error)")
                return
            }
            // Expected path
        } catch {
            Issue.record("Expected ChatSessionError.timeout, got \(error)")
        }
    }

    @Test("withTimeout returns result when operation completes before deadline")
    func withTimeoutSucceeds() async throws {
        let result = try await RetryHelper.withTimeout(.seconds(5)) {
            return "fast result"
        }
        #expect(result == "fast result")
    }

    @Test("withTimeout propagates non-timeout errors from the operation")
    func withTimeoutPropagatesError() async throws {
        do {
            _ = try await RetryHelper.withTimeout(.seconds(5)) {
                throw CopilotServiceError.notConfigured
            } as String
            Issue.record("Expected error to be thrown")
        } catch let error as CopilotServiceError {
            guard case .notConfigured = error else {
                Issue.record("Expected notConfigured, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Default configuration has expected values")
    func defaultConfiguration() {
        let config = RetryConfiguration.default
        #expect(config.maxAttempts == 3)
        #expect(config.baseDelay == 1.0)
        #expect(config.maxDelay == 30.0)
        #expect(config.retryableStatusCodes == [429, 502, 503, 504])
    }

    @Test("Does not retry Copilot httpError with non-retryable status")
    func doesNotRetryCopilotNonRetryable() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: 0.01,
            maxDelay: 0.1,
            retryableStatusCodes: [429, 502, 503, 504]
        )

        do {
            _ = try await RetryHelper.withRetry(configuration: config) {
                counter.increment()
                throw CopilotServiceError.httpError(statusCode: 400, message: "Bad Request")
            } as String
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(counter.count == 1)
        }
    }
}

// MARK: - RetryConfiguration Tests

@Suite("RetryConfiguration Tests")
struct RetryConfigurationTests {

    @Test("Custom configuration preserves values")
    func customConfiguration() {
        let config = RetryConfiguration(
            maxAttempts: 5,
            baseDelay: 2.0,
            maxDelay: 60.0,
            retryableStatusCodes: [429, 500, 502, 503, 504]
        )
        #expect(config.maxAttempts == 5)
        #expect(config.baseDelay == 2.0)
        #expect(config.maxDelay == 60.0)
        #expect(config.retryableStatusCodes.contains(500))
    }
}
