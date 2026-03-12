import Foundation

// MARK: - File Change Type

/// What kind of change to a file.
enum FileChangeType: String, Codable, Sendable {
    case create
    case modify
    case delete

    var displayName: String {
        switch self {
        case .create: "New File"
        case .modify: "Modified"
        case .delete: "Deleted"
        }
    }

    var icon: String {
        switch self {
        case .create: "plus.circle.fill"
        case .modify: "pencil.circle.fill"
        case .delete: "minus.circle.fill"
        }
    }
}

// MARK: - File Change

/// Represents a single file change extracted from an AI response.
/// Contains the file path, the type of change, and the full new content.
@Observable
final class FileChange: Identifiable {
    let id: UUID
    let filePath: String
    let language: String
    let changeType: FileChangeType
    let content: String
    var isApplied: Bool
    var isRejected: Bool
    var applyError: String?

    init(
        id: UUID = UUID(),
        filePath: String,
        language: String = "",
        changeType: FileChangeType = .modify,
        content: String,
        isApplied: Bool = false,
        isRejected: Bool = false,
        applyError: String? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.language = language
        self.changeType = changeType
        self.content = content
        self.isApplied = isApplied
        self.isRejected = isRejected
        self.applyError = applyError
    }

    /// The file name (last path component).
    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// The directory containing the file.
    var directory: String {
        (filePath as NSString).deletingLastPathComponent
    }

    /// Whether this change is pending (not applied and not rejected).
    var isPending: Bool {
        !isApplied && !isRejected
    }

    /// Approximate line count of the content.
    var lineCount: Int {
        content.components(separatedBy: "\n").count
    }
}

// MARK: - Change Set

/// A collection of file changes from a single AI response, ready to be
/// reviewed, applied, and committed together.
@Observable
final class ChangeSet: Identifiable {
    let id: UUID
    let ticketKey: String
    let description: String
    let createdAt: Date
    var changes: [FileChange]
    var commitMessage: String
    var isCommitted: Bool
    var branchName: String

    init(
        id: UUID = UUID(),
        ticketKey: String,
        description: String,
        createdAt: Date = Date(),
        changes: [FileChange] = [],
        commitMessage: String = "",
        isCommitted: Bool = false,
        branchName: String = ""
    ) {
        self.id = id
        self.ticketKey = ticketKey
        self.description = description
        self.createdAt = createdAt
        self.changes = changes
        self.commitMessage = commitMessage
        self.isCommitted = isCommitted
        self.branchName = branchName
    }

    /// How many changes are pending review.
    var pendingCount: Int {
        changes.filter(\.isPending).count
    }

    /// How many changes have been applied.
    var appliedCount: Int {
        changes.filter(\.isApplied).count
    }

    /// How many changes have been rejected.
    var rejectedCount: Int {
        changes.filter(\.isRejected).count
    }

    /// Whether all changes have been reviewed (applied or rejected).
    var isFullyReviewed: Bool {
        changes.allSatisfy { !$0.isPending }
    }

    /// Whether there are any applied changes ready to commit.
    var hasAppliedChanges: Bool {
        changes.contains(where: \.isApplied)
    }
}
