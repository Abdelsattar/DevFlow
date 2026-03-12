import Foundation

// MARK: - Git Client Errors

enum GitClientError: Error, LocalizedError {
    case notAGitRepository(String)
    case commandFailed(command: String, output: String, exitCode: Int32)
    case invalidPath(String)
    case branchAlreadyExists(String)
    case nothingToCommit

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "'\(path)' is not a git repository."
        case .commandFailed(let cmd, let output, let code):
            return "Git command failed (\(code)): \(cmd)\n\(output)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .branchAlreadyExists(let name):
            return "Branch '\(name)' already exists."
        case .nothingToCommit:
            return "Nothing to commit — working tree is clean."
        }
    }
}

// MARK: - Git Status Entry

/// Represents a single file's status in `git status --porcelain`.
struct GitStatusEntry: Identifiable, Sendable {
    let id = UUID()
    let indexStatus: Character
    let workTreeStatus: Character
    let path: String

    /// Human-readable status label.
    var statusLabel: String {
        switch (indexStatus, workTreeStatus) {
        case ("?", "?"): return "Untracked"
        case ("A", _):   return "Added"
        case ("M", _):   return "Modified"
        case (_, "M"):   return "Modified"
        case ("D", _):   return "Deleted"
        case (_, "D"):   return "Deleted"
        case ("R", _):   return "Renamed"
        case ("C", _):   return "Copied"
        default:         return "Changed"
        }
    }

    /// Whether this file has staged changes.
    var isStaged: Bool {
        indexStatus != " " && indexStatus != "?"
    }
}

// MARK: - Git Client

/// Executes local git commands via `Process`. All operations are scoped
/// to a specific repository directory.
@MainActor
final class GitClient {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Repository Info

    /// Check if a directory is a git repository.
    func isGitRepository(at path: String) async throws -> Bool {
        do {
            _ = try await run(["rev-parse", "--is-inside-work-tree"], in: path)
            return true
        } catch {
            return false
        }
    }

    /// Get the current branch name.
    func currentBranch(at path: String) async throws -> String {
        let output = try await run(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the repository root directory.
    func repositoryRoot(at path: String) async throws -> String {
        let output = try await run(["rev-parse", "--show-toplevel"], in: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the remote URL (origin).
    func remoteURL(at path: String) async throws -> String {
        let output = try await run(["remote", "get-url", "origin"], in: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Branch Operations

    /// Create and switch to a new branch.
    func createBranch(_ name: String, at path: String) async throws {
        // Check if branch already exists
        let branches = try await run(["branch", "--list", name], in: path)
        if !branches.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GitClientError.branchAlreadyExists(name)
        }

        _ = try await run(["checkout", "-b", name], in: path)
    }

    /// Switch to an existing branch.
    func checkout(_ branch: String, at path: String) async throws {
        _ = try await run(["checkout", branch], in: path)
    }

    /// List local branches.
    func listBranches(at path: String) async throws -> [String] {
        let output = try await run(["branch", "--list", "--format=%(refname:short)"], in: path)
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Status & Diff

    /// Get the working tree status as parsed entries.
    func status(at path: String) async throws -> [GitStatusEntry] {
        let output = try await run(["status", "--porcelain=v1"], in: path)
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitStatusEntry? in
                let str = String(line)
                guard str.count >= 4 else { return nil }
                let idx = str.index(str.startIndex, offsetBy: 0)
                let wt = str.index(str.startIndex, offsetBy: 1)
                let filePath = String(str.dropFirst(3))
                return GitStatusEntry(
                    indexStatus: str[idx],
                    workTreeStatus: str[wt],
                    path: filePath
                )
            }
    }

    /// Get the diff of unstaged changes.
    func diff(at path: String) async throws -> String {
        try await run(["diff"], in: path)
    }

    /// Get the diff of staged changes.
    func diffStaged(at path: String) async throws -> String {
        try await run(["diff", "--staged"], in: path)
    }

    /// Get the diff between current branch and another branch/ref.
    func diffBetween(_ base: String, _ head: String = "HEAD", at path: String) async throws -> String {
        try await run(["diff", "\(base)...\(head)"], in: path)
    }

    // MARK: - Staging & Committing

    /// Stage specific files.
    func add(_ files: [String], at path: String) async throws {
        _ = try await run(["add"] + files, in: path)
    }

    /// Stage all changes.
    func addAll(at path: String) async throws {
        _ = try await run(["add", "-A"], in: path)
    }

    /// Commit staged changes with a message.
    func commit(message: String, at path: String) async throws -> String {
        let output = try await run(["commit", "-m", message], in: path)
        return output
    }

    // MARK: - Push

    /// Push the current branch to origin.
    func push(at path: String, setUpstream: Bool = false) async throws {
        var args = ["push"]
        if setUpstream {
            let branch = try await currentBranch(at: path)
            args += ["-u", "origin", branch]
        }
        _ = try await run(args, in: path)
    }

    // MARK: - Log

    /// Get recent commit log entries.
    func log(count: Int = 10, at path: String) async throws -> String {
        try await run(["log", "--oneline", "-\(count)"], in: path)
    }

    // MARK: - Branch Name Generation

    /// Generate a branch name from a JIRA ticket key and summary.
    /// Format: `TICKET-123-short-description`
    nonisolated static func branchName(ticketKey: String, summary: String) -> String {
        let slug = summary
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(50)
        return "\(ticketKey)-\(slug)"
    }

    /// Generate a commit message from a JIRA ticket key and description.
    /// Format: `PLAT-123: Description`
    nonisolated static func commitMessage(ticketKey: String, description: String) -> String {
        "\(ticketKey): \(description)"
    }

    // MARK: - Private: Run Git Command

    /// Execute a git command and return its stdout.
    ///
    /// Pipe reads and `waitUntilExit` each run on separate `DispatchQueue.global()`
    /// threads — real OS threads that can block independently without stalling the
    /// Swift cooperative thread pool.  All three blocking calls start concurrently
    /// so a large stdout/stderr never deadlocks while we wait for the process to exit.
    @discardableResult
    private func run(_ arguments: [String], in directory: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: directory) else {
            throw GitClientError.invalidPath(directory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        // Inherit the full user environment so git can find SSH keys,
        // credential helpers, and user config, but force-disable interactive prompts.
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"]         = "echo"
        env["SSH_ASKPASS"]         = "echo"
        process.environment = env

        do {
            try process.run()
        } catch {
            throw GitClientError.commandFailed(
                command: "git \(arguments.joined(separator: " "))",
                output: error.localizedDescription,
                exitCode: -1
            )
        }

        // Launch three independent blocking operations on real OS threads so they
        // run concurrently.  Using DispatchQueue.global() keeps them off the Swift
        // cooperative pool and avoids pool-starvation deadlocks.
        async let stdoutData: Data = withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
        async let stderrData: Data = withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: stderrPipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
        async let exitStatus: Int32 = withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                cont.resume(returning: process.terminationStatus)
            }
        }

        let (outData, errData, status) = await (stdoutData, stderrData, exitStatus)
        let output      = String(data: outData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errData, encoding: .utf8) ?? ""

        if status == 0 {
            return output
        } else {
            throw GitClientError.commandFailed(
                command: "git \(arguments.joined(separator: " "))",
                output: errorOutput.isEmpty ? output : errorOutput,
                exitCode: status
            )
        }
    }
}
