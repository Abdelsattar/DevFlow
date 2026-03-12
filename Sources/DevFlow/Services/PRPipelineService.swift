import Foundation

// MARK: - PR Pipeline Result

/// The result of a successful PR pipeline execution.
struct PRPipelineResult: Sendable {
    let pullRequest: GitHubPullRequest
    let repoOwner: String
    let repoName: String
    let headBranch: String
    let baseBranch: String
    let stepLog: [String]
}

// MARK: - PR Pipeline Configuration

/// Configuration for the headless PR pipeline.
struct PRPipelineConfig {
    let prTitle: String
    let prBody: String
    let baseBranch: String?
    let transitionJira: Bool
    let targetJiraStatus: String
    let addJiraComment: Bool

    init(
        prTitle: String,
        prBody: String,
        baseBranch: String? = nil,
        transitionJira: Bool = true,
        targetJiraStatus: String = "In Review",
        addJiraComment: Bool = true
    ) {
        self.prTitle = prTitle
        self.prBody = prBody
        self.baseBranch = baseBranch
        self.transitionJira = transitionJira
        self.targetJiraStatus = targetJiraStatus
        self.addJiraComment = addJiraComment
    }
}

// MARK: - PR Pipeline Errors

enum PRPipelineError: Error, LocalizedError {
    case cannotResolveRepo(String)
    case pushFailed(String)
    case prCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotResolveRepo(let reason):
            return "Cannot resolve repository: \(reason)"
        case .pushFailed(let reason):
            return "Push failed: \(reason)"
        case .prCreationFailed(let reason):
            return "PR creation failed: \(reason)"
        }
    }
}

// MARK: - Repo Info

/// Resolved repository information for PR creation.
struct RepoInfo: Sendable {
    let owner: String
    let name: String
    let defaultBranch: String
    let headBranch: String
}

// MARK: - PR Pipeline Service

/// Headless service for push → PR → JIRA pipeline.
/// Extracted from PRCreationView so the orchestrator can call it programmatically.
@MainActor
enum PRPipelineService {

    /// Resolve repository info (owner, name, default branch, current branch).
    static func resolveRepoInfo(
        at repoPath: String,
        gitClient: GitClient,
        githubService: GitHubService
    ) async throws -> RepoInfo {
        let headBranch = try await gitClient.currentBranch(at: repoPath)

        let remoteURL = try await gitClient.remoteURL(at: repoPath)
        guard let parsed = GitHubService.parseRemoteURL(remoteURL) else {
            throw PRPipelineError.cannotResolveRepo("Cannot parse remote URL: \(remoteURL)")
        }

        var defaultBranch = "master"
        do {
            let repo = try await githubService.getRepository(owner: parsed.owner, name: parsed.name)
            defaultBranch = repo.defaultBranch
        } catch {
            // Keep "master" as fallback
        }

        return RepoInfo(
            owner: parsed.owner,
            name: parsed.name,
            defaultBranch: defaultBranch,
            headBranch: headBranch
        )
    }

    /// Execute the full push → PR → JIRA pipeline.
    static func executePRPipeline(
        ticket: JiraTicket,
        config: PRPipelineConfig,
        repoPath: String,
        gitClient: GitClient,
        githubService: GitHubService,
        jiraService: JiraService
    ) async throws -> PRPipelineResult {
        var stepLog: [String] = []

        // Resolve repo info
        let repoInfo = try await resolveRepoInfo(
            at: repoPath,
            gitClient: gitClient,
            githubService: githubService
        )

        let baseBranch = config.baseBranch ?? repoInfo.defaultBranch

        // Step 1: Push
        do {
            try await gitClient.push(at: repoPath, setUpstream: true)
            stepLog.append("Pushed \(repoInfo.headBranch) to origin")
        } catch {
            throw PRPipelineError.pushFailed(error.localizedDescription)
        }

        // Step 2: Create PR
        let pr: GitHubPullRequest
        do {
            pr = try await githubService.createPullRequest(
                owner: repoInfo.owner,
                repo: repoInfo.name,
                title: config.prTitle,
                body: config.prBody,
                head: repoInfo.headBranch,
                base: baseBranch
            )
            stepLog.append("Created PR #\(pr.number)")
        } catch {
            throw PRPipelineError.prCreationFailed(error.localizedDescription)
        }

        // Step 3: Update JIRA (non-fatal)
        if config.transitionJira {
            do {
                try await jiraService.transitionTicket(
                    key: ticket.key,
                    statusName: config.targetJiraStatus
                )
                stepLog.append("Transitioned \(ticket.key) to '\(config.targetJiraStatus)'")
            } catch {
                stepLog.append("JIRA transition failed: \(error.localizedDescription)")
            }
        }

        if config.addJiraComment {
            do {
                let comment = "Pull Request: \(pr.htmlUrl)"
                try await jiraService.addComment(key: ticket.key, body: comment)
                stepLog.append("Added PR link as JIRA comment")
            } catch {
                stepLog.append("JIRA comment failed: \(error.localizedDescription)")
            }
        }

        return PRPipelineResult(
            pullRequest: pr,
            repoOwner: repoInfo.owner,
            repoName: repoInfo.name,
            headBranch: repoInfo.headBranch,
            baseBranch: baseBranch,
            stepLog: stepLog
        )
    }
}
