import Foundation
import os
import SwiftData

/// Service responsible for persisting and restoring chat sessions using SwiftData.
/// Operates on a dedicated ModelContext to avoid UI thread contention during saves.
@MainActor
final class ChatPersistenceService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.devflow", category: "ChatPersistence")
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        // Merge policy: prefer in-memory state (we are the source of truth)
        self.modelContext.autosaveEnabled = false
    }

    // MARK: - Load

    /// Load all persisted chat sessions, ordered by most recent activity.
    func loadSessions() -> [ChatSession] {
        let descriptor = FetchDescriptor<PersistentChatSession>(
            sortBy: [SortDescriptor(\.lastActivityAt, order: .reverse)]
        )

        do {
            let persistentSessions = try modelContext.fetch(descriptor)
            return persistentSessions.map { $0.toChatSession() }
        } catch {
            Self.logger.error("Failed to load sessions: \(error.localizedDescription)")
            return []
        }
    }

    /// Load persisted sessions for a specific ticket key.
    func loadSessions(for ticketKey: String) -> [ChatSession] {
        let descriptor = FetchDescriptor<PersistentChatSession>(
            predicate: #Predicate { $0.ticketKey == ticketKey },
            sortBy: [SortDescriptor(\.lastActivityAt, order: .reverse)]
        )

        do {
            let persistentSessions = try modelContext.fetch(descriptor)
            return persistentSessions.map { $0.toChatSession() }
        } catch {
            Self.logger.error("Failed to load sessions for \(ticketKey): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Save

    /// Save a single chat session. If it already exists, updates it; otherwise inserts.
    func saveSession(_ session: ChatSession) {
        // Delete existing persistent session with same ID (full replace strategy)
        deletePersistedSession(id: session.id)

        // Insert the new snapshot
        let persistent = PersistentChatSession(from: session)
        modelContext.insert(persistent)

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save session \(session.id): \(error.localizedDescription)")
        }
    }

    /// Save multiple sessions at once (batch save).
    func saveSessions(_ sessions: [ChatSession]) {
        for session in sessions {
            deletePersistedSession(id: session.id)
            let persistent = PersistentChatSession(from: session)
            modelContext.insert(persistent)
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to batch save sessions: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    /// Delete a persisted session by ID.
    func deleteSession(id: UUID) {
        deletePersistedSession(id: id)

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to delete session \(id): \(error.localizedDescription)")
        }
    }

    /// Delete all persisted sessions (e.g. for a full reset).
    func deleteAllSessions() {
        do {
            try modelContext.delete(model: PersistentChatSession.self)
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to delete all sessions: \(error.localizedDescription)")
        }
    }

    /// Delete all sessions for a specific ticket.
    func deleteSessions(for ticketKey: String) {
        let descriptor = FetchDescriptor<PersistentChatSession>(
            predicate: #Predicate { $0.ticketKey == ticketKey }
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            for session in sessions {
                modelContext.delete(session)
            }
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to delete sessions for \(ticketKey): \(error.localizedDescription)")
        }
    }

    // MARK: - Housekeeping

    /// Remove sessions older than the specified number of days.
    func pruneOldSessions(olderThanDays days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<PersistentChatSession>(
            predicate: #Predicate { $0.lastActivityAt < cutoff }
        )

        do {
            let oldSessions = try modelContext.fetch(descriptor)
            for session in oldSessions {
                modelContext.delete(session)
            }
            if !oldSessions.isEmpty {
                try modelContext.save()
                Self.logger.info("Pruned \(oldSessions.count) old session(s)")
            }
        } catch {
            Self.logger.error("Failed to prune old sessions: \(error.localizedDescription)")
        }
    }

    /// Count of all persisted sessions (for diagnostics).
    func sessionCount() -> Int {
        let descriptor = FetchDescriptor<PersistentChatSession>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            return 0
        }
    }

    // MARK: - Private

    /// Delete the persistent session with the given ID from the context (without saving).
    private func deletePersistedSession(id: UUID) {
        let descriptor = FetchDescriptor<PersistentChatSession>(
            predicate: #Predicate { $0.sessionId == id }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            for session in existing {
                modelContext.delete(session)
            }
        } catch {
            // Swallow — the insert will still proceed
        }
    }
}
