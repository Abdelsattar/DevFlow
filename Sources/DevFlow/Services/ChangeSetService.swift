import Foundation

// MARK: - ChangeSet Service Errors

enum ChangeSetServiceError: Error, LocalizedError {
    case noChangesToApply
    case applyFailed(path: String, reason: String)
    case commitFailed(String)

    var errorDescription: String? {
        switch self {
        case .noChangesToApply:
            return "No changes to apply."
        case .applyFailed(let path, let reason):
            return "Failed to apply '\(path)': \(reason)"
        case .commitFailed(let reason):
            return "Commit failed: \(reason)"
        }
    }
}

// MARK: - ChangeSet Service

/// Headless service for applying file changes to disk and committing them.
/// Extracted from DiffPreviewView so the orchestrator can call these
/// operations programmatically.
@MainActor
enum ChangeSetService {

    /// Apply a single file change to disk at the given base path.
    /// Disk I/O is performed on a background thread to avoid blocking the main actor.
    static func applyChange(_ change: FileChange, basePath: String) async throws {
        let fullPath = (basePath as NSString).appendingPathComponent(change.filePath)
        let changeType = change.changeType
        let content = change.content

        try await Task.detached(priority: .userInitiated) {
            try ChangeSetService.writeFileToDisk(changeType: changeType, fullPath: fullPath, content: content)
        }.value

        change.isApplied = true
        change.isRejected = false
        change.applyError = nil
    }

    /// Apply all pending changes in a change set to disk.
    /// Throws on the first failure after marking the individual change's error.
    static func applyAllChanges(_ changeSet: ChangeSet, basePath: String) async throws {
        let pending = changeSet.changes.filter(\.isPending)
        guard !pending.isEmpty else { throw ChangeSetServiceError.noChangesToApply }

        for change in pending {
            do {
                try await applyChange(change, basePath: basePath)
            } catch {
                change.applyError = error.localizedDescription
                throw ChangeSetServiceError.applyFailed(
                    path: change.filePath,
                    reason: error.localizedDescription
                )
            }
        }
    }

    /// Stage all changes and commit with the given message.
    static func commitChanges(
        _ changeSet: ChangeSet,
        at repoPath: String,
        gitClient: GitClient
    ) async throws {
        guard changeSet.hasAppliedChanges else {
            throw ChangeSetServiceError.noChangesToApply
        }

        let message = changeSet.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw ChangeSetServiceError.commitFailed("Commit message is empty")
        }

        try await gitClient.addAll(at: repoPath)
        _ = try await gitClient.commit(message: message, at: repoPath)
        changeSet.isCommitted = true
    }

    // MARK: - Private

    /// Pure disk-write helper — runs on whichever thread calls it (intended for background threads).
    nonisolated private static func writeFileToDisk(
        changeType: FileChangeType,
        fullPath: String,
        content: String
    ) throws {
        if changeType == .delete {
            try FileManager.default.removeItem(atPath: fullPath)
        } else {
            let dir = (fullPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true
            )
            try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
        }
    }
}
