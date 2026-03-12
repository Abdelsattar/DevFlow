import Testing
import Foundation
import SwiftData
@testable import DevFlow

// MARK: - Persistent Model Conversion Tests

@Suite("PersistentChatMessage Conversion Tests")
struct PersistentChatMessageTests {

    @Test("Convert ChatMessage to PersistentChatMessage and back")
    func roundTripMessage() {
        let original = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Hello, here is the plan.",
            timestamp: Date(),
            isStreaming: false
        )

        let persistent = PersistentChatMessage(from: original, sortIndex: 3)
        let restored = persistent.toChatMessage()

        #expect(restored.id == original.id)
        #expect(restored.role == .assistant)
        #expect(restored.content == "Hello, here is the plan.")
        #expect(restored.isStreaming == false) // Always false on restore
        #expect(persistent.sortIndex == 3)
    }

    @Test("Streaming message restores as non-streaming")
    func streamingRestoredAsNonStreaming() {
        let streaming = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "partial content...",
            timestamp: Date(),
            isStreaming: true
        )

        let persistent = PersistentChatMessage(from: streaming, sortIndex: 0)
        let restored = persistent.toChatMessage()

        #expect(restored.isStreaming == false)
        #expect(restored.content == "partial content...")
    }

    @Test("System message round-trips correctly")
    func systemMessageRoundTrip() {
        let system = ChatMessage.system("You are a helpful assistant.")
        let persistent = PersistentChatMessage(from: system, sortIndex: 0)
        let restored = persistent.toChatMessage()

        #expect(restored.role == .system)
        #expect(restored.content == "You are a helpful assistant.")
    }

    @Test("Invalid role raw value falls back to .user")
    func invalidRoleFallback() {
        let persistent = PersistentChatMessage(
            messageId: UUID(),
            roleRaw: "invalid_role",
            content: "test",
            timestamp: Date(),
            sortIndex: 0
        )
        let restored = persistent.toChatMessage()
        #expect(restored.role == .user)
    }
}

// MARK: - Persistent FileChange Conversion Tests

@Suite("PersistentFileChange Conversion Tests")
struct PersistentFileChangeTests {

    @Test("Convert FileChange to PersistentFileChange and back")
    func roundTripFileChange() {
        let original = FileChange(
            id: UUID(),
            filePath: "Sources/App/main.swift",
            language: "swift",
            changeType: .create,
            content: "import Foundation\nprint(\"Hello\")",
            isApplied: true,
            isRejected: false
        )

        let persistent = PersistentFileChange(from: original, sortIndex: 2)
        let restored = persistent.toFileChange()

        #expect(restored.id == original.id)
        #expect(restored.filePath == "Sources/App/main.swift")
        #expect(restored.language == "swift")
        #expect(restored.changeType == .create)
        #expect(restored.content == "import Foundation\nprint(\"Hello\")")
        #expect(restored.isApplied == true)
        #expect(restored.isRejected == false)
        #expect(persistent.sortIndex == 2)
    }

    @Test("Invalid changeType raw value falls back to .modify")
    func invalidChangeTypeFallback() {
        let persistent = PersistentFileChange(
            changeId: UUID(),
            filePath: "test.txt",
            language: "",
            changeTypeRaw: "unknown",
            content: "",
            isApplied: false,
            isRejected: false,
            sortIndex: 0
        )
        let restored = persistent.toFileChange()
        #expect(restored.changeType == .modify)
    }
}

// MARK: - Persistent ChangeSet Conversion Tests

@Suite("PersistentChangeSet Conversion Tests")
struct PersistentChangeSetTests {

    @Test("Convert ChangeSet to PersistentChangeSet and back")
    func roundTripChangeSet() {
        let change1 = FileChange(
            filePath: "file1.swift",
            language: "swift",
            changeType: .create,
            content: "// new file"
        )
        let change2 = FileChange(
            filePath: "file2.swift",
            language: "swift",
            changeType: .modify,
            content: "// modified"
        )

        let original = ChangeSet(
            id: UUID(),
            ticketKey: "PLAT-123",
            description: "Add new feature",
            changes: [change1, change2],
            commitMessage: "PLAT-123: Add new feature",
            isCommitted: true,
            branchName: "feature/plat-123-add-new-feature"
        )

        let persistent = PersistentChangeSet(from: original, sortIndex: 0)
        let restored = persistent.toChangeSet()

        #expect(restored.id == original.id)
        #expect(restored.ticketKey == "PLAT-123")
        #expect(restored.description == "Add new feature")
        #expect(restored.commitMessage == "PLAT-123: Add new feature")
        #expect(restored.isCommitted == true)
        #expect(restored.branchName == "feature/plat-123-add-new-feature")
        #expect(restored.changes.count == 2)
        #expect(restored.changes[0].filePath == "file1.swift")
        #expect(restored.changes[1].filePath == "file2.swift")
    }

    @Test("Empty changes round-trip correctly")
    func emptyChangesRoundTrip() {
        let original = ChangeSet(
            ticketKey: "PLAT-456",
            description: "Empty set"
        )

        let persistent = PersistentChangeSet(from: original, sortIndex: 0)
        let restored = persistent.toChangeSet()

        #expect(restored.changes.isEmpty)
        #expect(restored.ticketKey == "PLAT-456")
    }
}

// MARK: - Persistent ChatSession Conversion Tests

@Suite("PersistentChatSession Conversion Tests")
struct PersistentChatSessionTests {

    @Test("Convert ChatSession to PersistentChatSession and back")
    func roundTripSession() {
        let session = ChatSession(
            id: UUID(),
            ticketKey: "PLAT-789",
            ticketSummary: "Fix login bug",
            purpose: .implement,
            messages: [
                .system("You are a coding assistant."),
                .user("Implement the fix"),
                ChatMessage(role: .assistant, content: "Here's the implementation...")
            ]
        )

        let persistent = PersistentChatSession(from: session)
        let restored = persistent.toChatSession()

        #expect(restored.id == session.id)
        #expect(restored.ticketKey == "PLAT-789")
        #expect(restored.ticketSummary == "Fix login bug")
        #expect(restored.purpose == .implement)
        #expect(restored.messages.count == 3)
        #expect(restored.messages[0].role == .system)
        #expect(restored.messages[1].role == .user)
        #expect(restored.messages[2].role == .assistant)
        #expect(restored.isGenerating == false)
        #expect(restored.errorMessage == nil)
    }

    @Test("Session with change sets round-trips correctly")
    func sessionWithChangeSets() {
        let session = ChatSession(
            ticketKey: "PLAT-100",
            ticketSummary: "Add feature",
            purpose: .implement,
            changeSets: [
                ChangeSet(
                    ticketKey: "PLAT-100",
                    description: "Initial implementation",
                    changes: [
                        FileChange(filePath: "main.swift", content: "code")
                    ],
                    commitMessage: "PLAT-100: Initial implementation",
                    isCommitted: false,
                    branchName: "feature/plat-100"
                )
            ]
        )

        let persistent = PersistentChatSession(from: session)
        let restored = persistent.toChatSession()

        #expect(restored.changeSets.count == 1)
        #expect(restored.changeSets[0].ticketKey == "PLAT-100")
        #expect(restored.changeSets[0].changes.count == 1)
        #expect(restored.changeSets[0].changes[0].filePath == "main.swift")
    }

    @Test("Invalid purpose falls back to .general")
    func invalidPurposeFallback() {
        let persistent = PersistentChatSession(
            sessionId: UUID(),
            ticketKey: "TEST-1",
            ticketSummary: "Test",
            purposeRaw: "nonexistent",
            createdAt: Date(),
            lastActivityAt: Date()
        )
        let restored = persistent.toChatSession()
        #expect(restored.purpose == .general)
    }

    @Test("lastActivityAt uses latest message timestamp")
    func lastActivityTimestamp() {
        let earlyDate = Date(timeIntervalSince1970: 1000)
        let lateDate = Date(timeIntervalSince1970: 5000)

        let session = ChatSession(
            ticketKey: "TEST-2",
            ticketSummary: "Test",
            purpose: .plan,
            createdAt: earlyDate,
            messages: [
                ChatMessage(role: .system, content: "sys", timestamp: earlyDate),
                ChatMessage(role: .user, content: "hello", timestamp: lateDate)
            ]
        )

        let persistent = PersistentChatSession(from: session)
        #expect(persistent.lastActivityAt == lateDate)
    }

    @Test("Empty session has lastActivityAt equal to createdAt")
    func emptySessionTimestamp() {
        let date = Date(timeIntervalSince1970: 2000)
        let session = ChatSession(
            ticketKey: "TEST-3",
            ticketSummary: "Test",
            purpose: .general,
            createdAt: date,
            messages: []
        )

        let persistent = PersistentChatSession(from: session)
        #expect(persistent.lastActivityAt == date)
    }

    @Test("Message ordering is preserved via sortIndex")
    func messageOrdering() {
        let messages: [ChatMessage] = [
            .system("System prompt"),
            .user("First question"),
            ChatMessage(role: .assistant, content: "First answer"),
            .user("Second question"),
            ChatMessage(role: .assistant, content: "Second answer"),
        ]

        let session = ChatSession(
            ticketKey: "ORD-1",
            ticketSummary: "Order test",
            purpose: .general,
            messages: messages
        )

        let persistent = PersistentChatSession(from: session)
        let restored = persistent.toChatSession()

        #expect(restored.messages.count == 5)
        #expect(restored.messages[0].content == "System prompt")
        #expect(restored.messages[1].content == "First question")
        #expect(restored.messages[2].content == "First answer")
        #expect(restored.messages[3].content == "Second question")
        #expect(restored.messages[4].content == "Second answer")
    }
}

// MARK: - ChatPersistenceService Tests

@Suite("ChatPersistenceService Tests")
struct ChatPersistenceServiceTests {

    /// Create an in-memory ModelContainer for testing.
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            PersistentChatSession.self,
            PersistentChatMessage.self,
            PersistentChangeSet.self,
            PersistentFileChange.self,
        ])
        let config = ModelConfiguration(
            "TestChat",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    @Test("Save and load a session")
    func saveAndLoad() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        let session = ChatSession(
            ticketKey: "SAVE-1",
            ticketSummary: "Save test",
            purpose: .plan,
            messages: [
                .system("System"),
                .user("Hello"),
                ChatMessage(role: .assistant, content: "Hi there!")
            ]
        )

        service.saveSession(session)

        let loaded = service.loadSessions()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == session.id)
        #expect(loaded[0].ticketKey == "SAVE-1")
        #expect(loaded[0].messages.count == 3)
        #expect(loaded[0].purpose == .plan)
    }

    @MainActor
    @Test("Delete a session")
    func deleteSession() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        let session = ChatSession(
            ticketKey: "DEL-1",
            ticketSummary: "Delete test",
            purpose: .general
        )

        service.saveSession(session)
        #expect(service.sessionCount() == 1)

        service.deleteSession(id: session.id)
        #expect(service.sessionCount() == 0)
        #expect(service.loadSessions().isEmpty)
    }

    @MainActor
    @Test("Save overwrites existing session with same ID")
    func saveOverwrites() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        let sessionId = UUID()
        let session1 = ChatSession(
            id: sessionId,
            ticketKey: "OVR-1",
            ticketSummary: "First version",
            purpose: .plan,
            messages: [.system("v1")]
        )
        service.saveSession(session1)

        // Update the session with more messages
        let session2 = ChatSession(
            id: sessionId,
            ticketKey: "OVR-1",
            ticketSummary: "First version",
            purpose: .plan,
            messages: [.system("v1"), .user("Added message")]
        )
        service.saveSession(session2)

        let loaded = service.loadSessions()
        #expect(loaded.count == 1)
        #expect(loaded[0].messages.count == 2)
    }

    @MainActor
    @Test("Load sessions for a specific ticket key")
    func loadSessionsForTicket() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        let session1 = ChatSession(ticketKey: "TKT-1", ticketSummary: "T1", purpose: .plan)
        let session2 = ChatSession(ticketKey: "TKT-1", ticketSummary: "T1", purpose: .implement)
        let session3 = ChatSession(ticketKey: "TKT-2", ticketSummary: "T2", purpose: .review)

        service.saveSessions([session1, session2, session3])

        let tkt1Sessions = service.loadSessions(for: "TKT-1")
        #expect(tkt1Sessions.count == 2)

        let tkt2Sessions = service.loadSessions(for: "TKT-2")
        #expect(tkt2Sessions.count == 1)
        #expect(tkt2Sessions[0].purpose == .review)
    }

    @MainActor
    @Test("Delete all sessions")
    func deleteAllSessions() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        service.saveSessions([
            ChatSession(ticketKey: "A-1", ticketSummary: "A", purpose: .plan),
            ChatSession(ticketKey: "B-1", ticketSummary: "B", purpose: .implement),
            ChatSession(ticketKey: "C-1", ticketSummary: "C", purpose: .review),
        ])

        #expect(service.sessionCount() == 3)

        service.deleteAllSessions()
        #expect(service.sessionCount() == 0)
    }

    @MainActor
    @Test("Delete sessions for a specific ticket")
    func deleteSessionsForTicket() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        service.saveSessions([
            ChatSession(ticketKey: "TKT-A", ticketSummary: "A", purpose: .plan),
            ChatSession(ticketKey: "TKT-A", ticketSummary: "A", purpose: .implement),
            ChatSession(ticketKey: "TKT-B", ticketSummary: "B", purpose: .review),
        ])

        service.deleteSessions(for: "TKT-A")

        #expect(service.sessionCount() == 1)
        let remaining = service.loadSessions()
        #expect(remaining[0].ticketKey == "TKT-B")
    }

    @MainActor
    @Test("Session count returns correct value")
    func sessionCount() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        #expect(service.sessionCount() == 0)

        service.saveSession(ChatSession(ticketKey: "CNT-1", ticketSummary: "C", purpose: .general))
        #expect(service.sessionCount() == 1)

        service.saveSession(ChatSession(ticketKey: "CNT-2", ticketSummary: "C", purpose: .general))
        #expect(service.sessionCount() == 2)
    }

    @MainActor
    @Test("Prune removes old sessions and keeps recent ones")
    func pruneOldSessions() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        // Create an old session (40 days ago)
        let oldDate = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        let oldSession = ChatSession(
            ticketKey: "OLD-1",
            ticketSummary: "Old session",
            purpose: .plan,
            createdAt: oldDate,
            messages: [ChatMessage(role: .system, content: "old", timestamp: oldDate)]
        )

        // Create a recent session
        let recentSession = ChatSession(
            ticketKey: "NEW-1",
            ticketSummary: "Recent session",
            purpose: .plan
        )

        service.saveSessions([oldSession, recentSession])
        #expect(service.sessionCount() == 2)

        service.pruneOldSessions(olderThanDays: 30)

        #expect(service.sessionCount() == 1)
        let remaining = service.loadSessions()
        #expect(remaining[0].ticketKey == "NEW-1")
    }

    @MainActor
    @Test("Save session with change sets persists file changes")
    func saveSessionWithChangeSets() throws {
        let container = try makeInMemoryContainer()
        let service = ChatPersistenceService(modelContainer: container)

        let session = ChatSession(
            ticketKey: "CS-1",
            ticketSummary: "Change set test",
            purpose: .implement,
            messages: [.system("System")],
            changeSets: [
                ChangeSet(
                    ticketKey: "CS-1",
                    description: "Feature implementation",
                    changes: [
                        FileChange(filePath: "a.swift", language: "swift", changeType: .create, content: "// new"),
                        FileChange(filePath: "b.swift", language: "swift", changeType: .modify, content: "// mod"),
                    ],
                    commitMessage: "CS-1: Feature implementation",
                    isCommitted: true,
                    branchName: "feature/cs-1"
                )
            ]
        )

        service.saveSession(session)

        let loaded = service.loadSessions()
        #expect(loaded.count == 1)
        #expect(loaded[0].changeSets.count == 1)
        #expect(loaded[0].changeSets[0].changes.count == 2)
        #expect(loaded[0].changeSets[0].isCommitted == true)
        #expect(loaded[0].changeSets[0].changes[0].filePath == "a.swift")
        #expect(loaded[0].changeSets[0].changes[1].filePath == "b.swift")
    }
}
