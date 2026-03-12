import Foundation
import SwiftData

// MARK: - Persistent Chat Message

/// SwiftData model for persisting chat messages across app restarts.
/// This is the storage counterpart of the in-memory `ChatMessage` struct.
@Model
final class PersistentChatMessage {
    // Use @Attribute(.unique) on the UUID to prevent duplicates
    @Attribute(.unique)
    var messageId: UUID

    var roleRaw: String
    var content: String
    var timestamp: Date

    /// The session this message belongs to (inverse relationship).
    var session: PersistentChatSession?

    /// Sort index to preserve message ordering within a session.
    var sortIndex: Int

    init(
        messageId: UUID,
        roleRaw: String,
        content: String,
        timestamp: Date,
        sortIndex: Int
    ) {
        self.messageId = messageId
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
        self.sortIndex = sortIndex
    }

    // MARK: - Conversion

    /// Convert from in-memory ChatMessage.
    convenience init(from message: ChatMessage, sortIndex: Int) {
        self.init(
            messageId: message.id,
            roleRaw: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp,
            sortIndex: sortIndex
        )
    }

    /// Convert to in-memory ChatMessage.
    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: messageId,
            role: ChatRole(rawValue: roleRaw) ?? .user,
            content: content,
            timestamp: timestamp,
            isStreaming: false  // Never restore as streaming
        )
    }
}

// MARK: - Persistent File Change

/// SwiftData model for persisting file changes within a change set.
@Model
final class PersistentFileChange {
    @Attribute(.unique)
    var changeId: UUID

    var filePath: String
    var language: String
    var changeTypeRaw: String
    var content: String
    var isApplied: Bool
    var isRejected: Bool

    /// The change set this file change belongs to.
    var changeSet: PersistentChangeSet?

    /// Sort index to preserve ordering.
    var sortIndex: Int

    init(
        changeId: UUID,
        filePath: String,
        language: String,
        changeTypeRaw: String,
        content: String,
        isApplied: Bool,
        isRejected: Bool,
        sortIndex: Int
    ) {
        self.changeId = changeId
        self.filePath = filePath
        self.language = language
        self.changeTypeRaw = changeTypeRaw
        self.content = content
        self.isApplied = isApplied
        self.isRejected = isRejected
        self.sortIndex = sortIndex
    }

    /// Convert from in-memory FileChange.
    convenience init(from fileChange: FileChange, sortIndex: Int) {
        self.init(
            changeId: fileChange.id,
            filePath: fileChange.filePath,
            language: fileChange.language,
            changeTypeRaw: fileChange.changeType.rawValue,
            content: fileChange.content,
            isApplied: fileChange.isApplied,
            isRejected: fileChange.isRejected,
            sortIndex: sortIndex
        )
    }

    /// Convert to in-memory FileChange.
    func toFileChange() -> FileChange {
        FileChange(
            id: changeId,
            filePath: filePath,
            language: language,
            changeType: FileChangeType(rawValue: changeTypeRaw) ?? .modify,
            content: content,
            isApplied: isApplied,
            isRejected: isRejected
        )
    }
}

// MARK: - Persistent Change Set

/// SwiftData model for persisting change sets extracted from AI responses.
@Model
final class PersistentChangeSet {
    @Attribute(.unique)
    var changeSetId: UUID

    var ticketKey: String
    var changeSetDescription: String
    var createdAt: Date
    var commitMessage: String
    var isCommitted: Bool
    var branchName: String

    /// File changes in this change set.
    @Relationship(deleteRule: .cascade, inverse: \PersistentFileChange.changeSet)
    var changes: [PersistentFileChange]

    /// The session this change set belongs to.
    var session: PersistentChatSession?

    /// Sort index to preserve ordering.
    var sortIndex: Int

    init(
        changeSetId: UUID,
        ticketKey: String,
        changeSetDescription: String,
        createdAt: Date,
        commitMessage: String,
        isCommitted: Bool,
        branchName: String,
        changes: [PersistentFileChange] = [],
        sortIndex: Int
    ) {
        self.changeSetId = changeSetId
        self.ticketKey = ticketKey
        self.changeSetDescription = changeSetDescription
        self.createdAt = createdAt
        self.commitMessage = commitMessage
        self.isCommitted = isCommitted
        self.branchName = branchName
        self.changes = changes
        self.sortIndex = sortIndex
    }

    /// Convert from in-memory ChangeSet.
    convenience init(from changeSet: ChangeSet, sortIndex: Int) {
        let persistentChanges = changeSet.changes.enumerated().map { index, change in
            PersistentFileChange(from: change, sortIndex: index)
        }
        self.init(
            changeSetId: changeSet.id,
            ticketKey: changeSet.ticketKey,
            changeSetDescription: changeSet.description,
            createdAt: changeSet.createdAt,
            commitMessage: changeSet.commitMessage,
            isCommitted: changeSet.isCommitted,
            branchName: changeSet.branchName,
            changes: persistentChanges,
            sortIndex: sortIndex
        )
    }

    /// Convert to in-memory ChangeSet.
    func toChangeSet() -> ChangeSet {
        let sortedChanges = changes.sorted { $0.sortIndex < $1.sortIndex }
        return ChangeSet(
            id: changeSetId,
            ticketKey: ticketKey,
            description: changeSetDescription,
            createdAt: createdAt,
            changes: sortedChanges.map { $0.toFileChange() },
            commitMessage: commitMessage,
            isCommitted: isCommitted,
            branchName: branchName
        )
    }
}

// MARK: - Persistent Chat Session

/// SwiftData model for persisting chat sessions across app restarts.
/// This is the storage counterpart of the in-memory `ChatSession` class.
@Model
final class PersistentChatSession {
    @Attribute(.unique)
    var sessionId: UUID

    var ticketKey: String
    var ticketSummary: String
    var purposeRaw: String
    var createdAt: Date
    var lastActivityAt: Date

    /// Messages in this session, ordered by sortIndex.
    @Relationship(deleteRule: .cascade, inverse: \PersistentChatMessage.session)
    var messages: [PersistentChatMessage]

    /// Change sets extracted in this session.
    @Relationship(deleteRule: .cascade, inverse: \PersistentChangeSet.session)
    var changeSets: [PersistentChangeSet]

    init(
        sessionId: UUID,
        ticketKey: String,
        ticketSummary: String,
        purposeRaw: String,
        createdAt: Date,
        lastActivityAt: Date,
        messages: [PersistentChatMessage] = [],
        changeSets: [PersistentChangeSet] = []
    ) {
        self.sessionId = sessionId
        self.ticketKey = ticketKey
        self.ticketSummary = ticketSummary
        self.purposeRaw = purposeRaw
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.messages = messages
        self.changeSets = changeSets
    }

    /// Convert from in-memory ChatSession.
    convenience init(from session: ChatSession) {
        let persistentMessages = session.messages.enumerated().map { index, message in
            PersistentChatMessage(from: message, sortIndex: index)
        }
        let persistentChangeSets = session.changeSets.enumerated().map { index, changeSet in
            PersistentChangeSet(from: changeSet, sortIndex: index)
        }
        self.init(
            sessionId: session.id,
            ticketKey: session.ticketKey,
            ticketSummary: session.ticketSummary,
            purposeRaw: session.purpose.rawValue,
            createdAt: session.createdAt,
            lastActivityAt: session.messages.last?.timestamp ?? session.createdAt,
            messages: persistentMessages,
            changeSets: persistentChangeSets
        )
    }

    /// Convert to in-memory ChatSession.
    func toChatSession() -> ChatSession {
        let sortedMessages = messages.sorted { $0.sortIndex < $1.sortIndex }
        let sortedChangeSets = changeSets.sorted { $0.sortIndex < $1.sortIndex }
        return ChatSession(
            id: sessionId,
            ticketKey: ticketKey,
            ticketSummary: ticketSummary,
            purpose: ChatPurpose(rawValue: purposeRaw) ?? .general,
            createdAt: createdAt,
            messages: sortedMessages.map { $0.toChatMessage() },
            changeSets: sortedChangeSets.map { $0.toChangeSet() }
        )
    }
}

// MARK: - Persistent Autonomous Flow Run

/// SwiftData model for persisting autonomous flow runs across app restarts.
/// Mirrors the in-memory `AutonomousFlowRun` for crash recovery.
@Model
final class PersistentAutonomousFlowRun {
    @Attribute(.unique)
    var runId: UUID

    var ticketKey: String
    var ticketSummary: String
    var stageRaw: String
    var approvalModeRaw: String
    var stageLogData: Data?
    var planSessionId: UUID?
    var implementSessionId: UUID?
    var reviewSessionId: UUID?
    var reworkSessionId: UUID?
    var changeSetId: UUID?
    var createdBranch: String?
    var errorMessage: String?
    var reworkCount: Int
    var startedAt: Date
    var completedAt: Date?

    init(
        runId: UUID,
        ticketKey: String,
        ticketSummary: String,
        stageRaw: String,
        approvalModeRaw: String,
        stageLogData: Data? = nil,
        planSessionId: UUID? = nil,
        implementSessionId: UUID? = nil,
        reviewSessionId: UUID? = nil,
        reworkSessionId: UUID? = nil,
        changeSetId: UUID? = nil,
        createdBranch: String? = nil,
        errorMessage: String? = nil,
        reworkCount: Int = 0,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.runId = runId
        self.ticketKey = ticketKey
        self.ticketSummary = ticketSummary
        self.stageRaw = stageRaw
        self.approvalModeRaw = approvalModeRaw
        self.stageLogData = stageLogData
        self.planSessionId = planSessionId
        self.implementSessionId = implementSessionId
        self.reviewSessionId = reviewSessionId
        self.reworkSessionId = reworkSessionId
        self.changeSetId = changeSetId
        self.createdBranch = createdBranch
        self.errorMessage = errorMessage
        self.reworkCount = reworkCount
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Convert from in-memory AutonomousFlowRun.
    @MainActor
    convenience init(from run: AutonomousFlowRun) {
        let logData = try? JSONEncoder().encode(run.stageLog)
        self.init(
            runId: run.id,
            ticketKey: run.ticketKey,
            ticketSummary: run.ticketSummary,
            stageRaw: run.stage.rawValue,
            approvalModeRaw: run.approvalMode.rawValue,
            stageLogData: logData,
            planSessionId: run.planSessionId,
            implementSessionId: run.implementSessionId,
            reviewSessionId: run.reviewSessionId,
            reworkSessionId: run.reworkSessionId,
            changeSetId: run.changeSetId,
            createdBranch: run.createdBranch,
            errorMessage: run.errorMessage,
            reworkCount: run.reworkCount,
            startedAt: run.startedAt,
            completedAt: run.completedAt
        )
    }

    /// Convert to in-memory AutonomousFlowRun.
    /// Interrupted (non-terminal) runs are marked as failed.
    @MainActor
    func toFlowRun() -> AutonomousFlowRun {
        let stage = AutonomousFlowStage(rawValue: stageRaw) ?? .failed
        let approvalMode = AutonomousFlowApprovalMode(rawValue: approvalModeRaw) ?? .fullyAutonomous
        var stageLog: [StageLogEntry] = []
        if let data = stageLogData {
            stageLog = (try? JSONDecoder().decode([StageLogEntry].self, from: data)) ?? []
        }

        let run = AutonomousFlowRun(
            id: runId,
            ticketKey: ticketKey,
            ticketSummary: ticketSummary,
            approvalMode: approvalMode,
            stage: stage.isTerminal ? stage : .failed,
            stageLog: stageLog,
            reworkCount: reworkCount
        )
        run.planSessionId = planSessionId
        run.implementSessionId = implementSessionId
        run.reviewSessionId = reviewSessionId
        run.reworkSessionId = reworkSessionId
        run.changeSetId = changeSetId
        run.createdBranch = createdBranch
        run.errorMessage = stage.isTerminal ? errorMessage : "Run interrupted — app was terminated"
        run.completedAt = completedAt
        return run
    }
}
