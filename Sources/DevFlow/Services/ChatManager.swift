import Foundation
import os
import SwiftData

/// Errors from headless chat session execution.
enum ChatSessionError: Error, LocalizedError {
    case aiFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .aiFailed(let message): return "AI session failed: \(message)"
        case .timeout: return "Chat session timed out."
        }
    }
}

/// Manages multiple concurrent chat sessions. Provides creation, switching,
/// and orchestration of AI interactions via CopilotService.
/// Persists sessions to SwiftData so they survive app restarts.
@MainActor
@Observable
final class ChatManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.devflow", category: "ChatManager")

    // MARK: - State

    /// All active chat sessions, ordered by most recently created.
    var sessions: [ChatSession] = []

    /// The currently visible/active chat session ID.
    var activeSessionId: UUID?

    /// Whether sessions have been loaded from persistence.
    var hasLoadedPersistedSessions: Bool = false

    // MARK: - Dependencies

    private let appState: AppState

    // MARK: - Persistence

    @ObservationIgnored
    private var persistenceService: ChatPersistenceService?

    // MARK: - Task Tracking

    /// In-flight streaming tasks keyed by session ID, for proper cancellation.
    @ObservationIgnored
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    /// Debounce timer for batching saves.
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
    }

    /// Configure persistence with a ModelContainer. Call this once after init.
    func configurePersistence(modelContainer: ModelContainer) {
        self.persistenceService = ChatPersistenceService(modelContainer: modelContainer)
    }

    /// Load previously persisted sessions. Call once on app startup after configurePersistence.
    func loadPersistedSessions() {
        guard let persistence = persistenceService else { return }
        guard !hasLoadedPersistedSessions else { return }

        // Prune sessions older than 30 days
        persistence.pruneOldSessions(olderThanDays: 30)

        let restored = persistence.loadSessions()
        if !restored.isEmpty {
            sessions = restored
            // Activate the most recent session
            activeSessionId = sessions.first?.id
        }

        hasLoadedPersistedSessions = true
        Self.logger.info("Restored \(restored.count) session(s) from persistence")
    }

    // MARK: - Computed

    /// The currently active chat session.
    var activeSession: ChatSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    /// All sessions for a given ticket key.
    func sessions(for ticketKey: String) -> [ChatSession] {
        sessions.filter { $0.ticketKey == ticketKey }
    }

    /// Whether there's an active chat view to show.
    var hasActiveChat: Bool {
        activeSessionId != nil
    }

    // MARK: - Session Management

    /// Create a new chat session for a ticket with the given purpose.
    /// Automatically builds the system prompt from ticket context and makes it active.
    @discardableResult
    func createSession(
        ticket: JiraTicket,
        purpose: ChatPurpose
    ) -> ChatSession {
        let systemPrompt = PromptBuilder.buildSystemPrompt(
            ticket: ticket,
            purpose: purpose
        )

        let session = ChatSession(
            ticketKey: ticket.key,
            ticketSummary: ticket.fields.summary,
            purpose: purpose,
            messages: [.system(systemPrompt)]
        )

        sessions.insert(session, at: 0)
        activeSessionId = session.id

        // Persist the new session
        scheduleSave(session)

        // Auto-send the initial user message for plan/implement/review
        let initialMessage = PromptBuilder.buildInitialUserMessage(purpose: purpose)
        if let initialMessage {
            session.addUserMessage(initialMessage)
            // Kick off the AI response, storing the task for cancellation
            let task = Task {
                await sendToAI(session: session)
            }
            activeTasks[session.id] = task
        }

        return session
    }

    /// Switch to an existing session.
    func switchTo(session: ChatSession) {
        activeSessionId = session.id
    }

    /// Switch to a session by ID.
    func switchTo(sessionId: UUID) {
        activeSessionId = sessionId
    }

    /// Close/remove a chat session. Cancels any in-flight streaming task.
    func closeSession(_ session: ChatSession) {
        // Cancel any in-flight task for this session
        cancelTask(for: session.id)

        let sessionId = session.id
        sessions.removeAll { $0.id == sessionId }
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
        }

        // Delete from persistence
        persistenceService?.deleteSession(id: sessionId)
    }

    /// Close a session by ID.
    func closeSession(id: UUID) {
        if let session = sessions.first(where: { $0.id == id }) {
            closeSession(session)
        }
    }

    /// Stop the AI from generating a response for the given session.
    func stopGenerating(session: ChatSession) {
        cancelTask(for: session.id)
        session.finishCurrentMessage()
        scheduleSave(session)
    }

    /// Stop generating for a session by ID.
    func stopGenerating(sessionId: UUID) {
        if let session = sessions.first(where: { $0.id == sessionId }) {
            stopGenerating(session: session)
        }
    }

    // MARK: - Messaging

    /// Send a user message in the given session and stream the AI response.
    func sendMessage(_ content: String, in session: ChatSession) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !session.isGenerating else { return }

        session.addUserMessage(content)
        scheduleSave(session)

        let task = Task {
            await sendToAI(session: session)
        }
        activeTasks[session.id] = task
        // Await the task so the caller can observe completion
        await task.value
    }

    /// Retry the last failed message in a session.
    func retry(session: ChatSession) async {
        session.errorMessage = nil

        let task = Task {
            await sendToAI(session: session)
        }
        activeTasks[session.id] = task
        await task.value
    }

    // MARK: - Persistence Triggers

    /// Notify that a change set was added/updated in a session (called from views).
    func sessionDidUpdateChangeSets(_ session: ChatSession) {
        scheduleSave(session)
    }

    /// Save all current sessions immediately (e.g. on app termination).
    func saveAllSessions() {
        guard let persistence = persistenceService else { return }
        persistence.saveSessions(sessions)
    }

    // MARK: - AI Interaction

    /// Run a chat session to completion — creates the session, waits for AI
    /// streaming to finish, and returns the completed session.
    /// This is the orchestrator's building block for headless AI interactions.
    ///
    /// - Parameters:
    ///   - ticket: The JIRA ticket for context.
    ///   - purpose: The chat purpose (plan, implement, review, general).
    ///   - additionalUserMessage: Optional extra user message to inject after the
    ///     initial message (e.g. plan context for implement, diff for review).
    ///   - timeout: Maximum duration to wait for completion. Defaults to 5 minutes.
    /// - Returns: The completed `ChatSession` with all messages.
    /// - Throws: If the session errors out, times out, or is cancelled.
    func runSessionToCompletion(
        ticket: JiraTicket,
        purpose: ChatPurpose,
        additionalUserMessage: String? = nil,
        timeout: Duration = .seconds(300)
    ) async throws -> ChatSession {
        let session = createSession(ticket: ticket, purpose: purpose)
        let sessionId = session.id

        // Watchdog inherits @MainActor isolation from this function. It fires after
        // `timeout`, marks the session with a known error marker, then cancels the
        // active AI streaming task so the await below unblocks.
        let watchdog = Task { [timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            session.setError(ChatManager.timeoutMarker)
            self.cancelTask(for: sessionId)
        }

        defer { watchdog.cancel() }

        // Wait for the initial auto-message that createSession kicked off.
        if let task = activeTasks[session.id] {
            await task.value
        }

        if let error = session.errorMessage {
            if error == ChatManager.timeoutMarker { throw ChatSessionError.timeout }
            throw ChatSessionError.aiFailed(error)
        }

        // Send additional context if provided, then wait for it to finish.
        if let extra = additionalUserMessage {
            await sendMessage(extra, in: session)
            if let error = session.errorMessage {
                if error == ChatManager.timeoutMarker { throw ChatSessionError.timeout }
                throw ChatSessionError.aiFailed(error)
            }
        }

        return session
    }

    // Sentinel used by the timeout watchdog in runSessionToCompletion.
    private static let timeoutMarker = "__jetflow_timeout__"

    /// Stream a response from the Copilot API for the given session.
    private func sendToAI(session: ChatSession) async {
        session.errorMessage = nil
        session.beginAssistantMessage()

        do {
            let stream = try await appState.copilotService.streamChatCompletion(
                messages: session.apiMessages
            )
            for try await chunk in stream {
                // Check for cancellation between chunks
                try Task.checkCancellation()
                session.appendToCurrentMessage(chunk)
            }
            session.finishCurrentMessage()
        } catch is CancellationError {
            session.finishCurrentMessage()
        } catch {
            session.setError(error.localizedDescription)
        }

        // Clean up task reference
        activeTasks.removeValue(forKey: session.id)

        // Persist after streaming completes
        scheduleSave(session)
    }

    // MARK: - Private

    /// Cancel and remove the task for a given session.
    private func cancelTask(for sessionId: UUID) {
        activeTasks[sessionId]?.cancel()
        activeTasks.removeValue(forKey: sessionId)
    }

    /// Schedule a debounced save for the given session.
    /// Coalesces rapid mutations (e.g. streaming chunks) into a single save
    /// after a short delay.
    private func scheduleSave(_ session: ChatSession) {
        guard persistenceService != nil else { return }

        saveTask?.cancel()
        let persistence = persistenceService
        let sessionSnapshot = session
        saveTask = Task { [persistence] in
            // Debounce: wait 500ms before saving to coalesce rapid updates
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistence?.saveSession(sessionSnapshot)
        }
    }
}
