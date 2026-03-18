import Foundation
import SwiftData

// MARK: - Orchestrator Errors

enum AutonomousFlowError: Error, LocalizedError {
    case preflightFailed(String)
    case alreadyRunning
    case noChangesExtracted
    case stageTimeout(AutonomousFlowStage)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .preflightFailed(let reason): return "Pre-flight check failed: \(reason)"
        case .alreadyRunning: return "Another autonomous flow is already running."
        case .noChangesExtracted: return "No code changes could be extracted from the AI response."
        case .stageTimeout(let stage): return "Stage '\(stage.displayName)' timed out."
        case .cancelled: return "Autonomous flow was cancelled."
        }
    }
}

// MARK: - Autonomous Flow Orchestrator

/// Orchestrates the full ticket-to-PR autonomous pipeline:
/// Branch → Plan → Implement → Apply → Commit → Review → (Rework) → Push → PR → JIRA → Done
///
/// Uses three purpose-specific AI sessions (plan, implement, review) on the same
/// Copilot backend, coordinated sequentially. Approval gates are configurable.
@MainActor
@Observable
final class AutonomousFlowOrchestrator {

    // MARK: - State

    /// The currently active run, if any.
    var activeRun: AutonomousFlowRun?

    /// Historical runs for display. Loaded from persistence on startup.
    var completedRuns: [AutonomousFlowRun] = []

    // MARK: - Dependencies

    private let appState: AppState

    // MARK: - Task Tracking

    @ObservationIgnored
    private var pipelineTask: Task<Void, Never>?

    // MARK: - Timeout Configuration

    /// Timeout for AI chat stages (plan, implement, review).
    var chatStageTimeout: Duration = .seconds(300)

    /// Timeout for git/PR stages (branch, push, PR creation).
    var gitStageTimeout: Duration = .seconds(120)

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public API

    /// Start a new autonomous flow run for the given ticket.
    @discardableResult
    func startRun(
        ticket: JiraTicket,
        approvalMode: AutonomousFlowApprovalMode
    ) throws -> AutonomousFlowRun {
        guard activeRun == nil else {
            throw AutonomousFlowError.alreadyRunning
        }

        let run = AutonomousFlowRun(
            ticketKey: ticket.key,
            ticketSummary: ticket.fields.summary,
            approvalMode: approvalMode
        )
        activeRun = run

        pipelineTask = Task {
            await executePipeline(run: run, ticket: ticket)
        }

        return run
    }

    /// Cancel the active run.
    func cancelRun() {
        guard let run = activeRun, !run.isFinished else { return }
        pipelineTask?.cancel()
        pipelineTask = nil
        run.cancel()
        persistRunState(run)
        finalizeRun(run)
    }

    /// Resume a run that's paused at an approval gate.
    func approveAndContinue() {
        guard let run = activeRun, run.isPaused else { return }

        let ticket = appState.tickets.first { $0.key == run.ticketKey }
        guard let ticket else {
            run.fail(message: "Ticket \(run.ticketKey) no longer available")
            persistRunState(run)
            finalizeRun(run)
            return
        }

        pipelineTask = Task {
            await executePipeline(run: run, ticket: ticket)
        }
    }

    /// Retry a failed run from the failed stage.
    func retryFailedStage() {
        guard let run = activeRun, run.stage == .failed else { return }

        let ticket = appState.tickets.first { $0.key == run.ticketKey }
        guard let ticket else {
            run.fail(message: "Ticket \(run.ticketKey) no longer available")
            return
        }

        run.errorMessage = nil
        pipelineTask = Task {
            await executePipeline(run: run, ticket: ticket)
        }
    }

    /// Load persisted runs on startup. Interrupted runs are marked as failed.
    func loadPersistedRuns() {
        guard let container = appState.modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentAutonomousFlowRun>()
        guard let persisted = try? context.fetch(descriptor) else { return }

        completedRuns = persisted.map { $0.toFlowRun() }
    }

    // MARK: - Pipeline Execution

    private func executePipeline(run: AutonomousFlowRun, ticket: JiraTicket) async {
        let repoPath = appState.workspacePath
        let chatManager = appState.chatManager
        let gitClient = appState.gitClient

        do {
            // If resuming from an approval gate, skip to the right stage
            if run.stage == .awaitingPlanApproval {
                // Continue from implement stage
                try await executeImplementStage(run: run, ticket: ticket, chatManager: chatManager)
                return
            }

            if run.stage == .awaitingImplApproval {
                // Continue from apply stage
                try await executeApplyAndBeyond(run: run, ticket: ticket, chatManager: chatManager, gitClient: gitClient, repoPath: repoPath)
                return
            }

            // If resuming from failed, pick up where we left off
            // For simplicity, re-run from the current stage
            if run.stage != .idle && run.stage != .failed {
                // Already in progress — shouldn't happen
                return
            }

            // Fresh start or retry from failed
            try Task.checkCancellation()

            // PRE-FLIGHT CHECKS (skip on retry if branch already created)
            if run.createdBranch == nil {
                run.advanceTo(.creatingBranch, message: "Running pre-flight checks...")
                try await preflightChecks(repoPath: repoPath, gitClient: gitClient)

                // STAGE 1: Create branch
                let branchName = GitClient.branchName(ticketKey: ticket.key, summary: ticket.fields.summary)
                try await gitClient.createBranch(branchName, at: repoPath)
                run.createdBranch = branchName
                run.advanceTo(.planning, message: "Created branch: \(branchName)")
                persistRunState(run)
            } else {
                // Retry after failure: branch already exists — switch to it
                let branchName = run.createdBranch!
                run.advanceTo(.creatingBranch, message: "Resuming on existing branch: \(branchName)")
                try await gitClient.checkout(branchName, at: repoPath)
                run.advanceTo(.planning, message: "Checked out branch: \(branchName)")
                persistRunState(run)
            }

            try Task.checkCancellation()

            // STAGE 2: Plan (skip if plan session already succeeded on a previous attempt)
            if run.planSessionId == nil {
                let planSession = try await chatManager.runSessionToCompletion(
                    ticket: ticket,
                    purpose: .plan,
                    timeout: chatStageTimeout
                )
                run.planSessionId = planSession.id
                let planContent = lastAssistantMessage(in: planSession)
                guard !planContent.isEmpty else {
                    throw AutonomousFlowError.preflightFailed("Plan session produced no output")
                }

                // Check for approval gate
                if run.approvalMode == .approveAfterPlan || run.approvalMode == .approveAfterBoth {
                    run.advanceTo(.awaitingPlanApproval, message: "Plan complete — awaiting approval")
                    persistRunState(run)
                    return
                }
            }

            run.advanceTo(.implementing, message: "Plan complete")
            persistRunState(run)

            try Task.checkCancellation()

            // STAGE 3: Implement (with plan context)
            try await executeImplementStage(run: run, ticket: ticket, chatManager: chatManager)

        } catch is CancellationError {
            if !run.isFinished {
                run.cancel()
                persistRunState(run)
                finalizeRun(run)
            }
        } catch {
            if !run.isFinished {
                run.fail(message: error.localizedDescription)
                persistRunState(run)
                NotificationService.shared.notifyAutonomousFlowFailed(
                    ticketKey: run.ticketKey,
                    stage: run.stage.displayName,
                    error: error.localizedDescription
                )
                // Don't finalize — allow retry
            }
        }
    }

    private func executeImplementStage(
        run: AutonomousFlowRun,
        ticket: JiraTicket,
        chatManager: ChatManager
    ) async throws {
        let repoPath = appState.workspacePath
        let gitClient = appState.gitClient

        try Task.checkCancellation()

        // Skip if the implement session already succeeded (retry path)
        if run.implementSessionId == nil {
            run.advanceTo(.implementing, message: "Starting implementation...")
            persistRunState(run)

            // Get plan content from the plan session
            let planContent: String
            if let planSessionId = run.planSessionId,
               let planSession = chatManager.sessions.first(where: { $0.id == planSessionId }) {
                planContent = lastAssistantMessage(in: planSession)
            } else {
                planContent = ""
            }

            let implMessage = planContent.isEmpty ? nil : PromptBuilder.buildImplementWithPlanContext(plan: planContent)
            let implSession = try await chatManager.runSessionToCompletion(
                ticket: ticket,
                purpose: .implement,
                additionalUserMessage: implMessage,
                timeout: chatStageTimeout
            )
            run.implementSessionId = implSession.id

            // Check for approval gate
            if run.approvalMode == .approveAfterBoth {
                run.advanceTo(.awaitingImplApproval, message: "Implementation complete — awaiting approval")
                persistRunState(run)
                return
            }
        }

        try await executeApplyAndBeyond(
            run: run,
            ticket: ticket,
            chatManager: chatManager,
            gitClient: gitClient,
            repoPath: repoPath
        )
    }

    private func executeApplyAndBeyond(
        run: AutonomousFlowRun,
        ticket: JiraTicket,
        chatManager: ChatManager,
        gitClient: GitClient,
        repoPath: String
    ) async throws {
        try Task.checkCancellation()

        // STAGE 4: Extract + Apply Changes
        run.advanceTo(.applyingChanges, message: "Extracting code changes...")
        persistRunState(run)

        guard let implSessionId = run.implementSessionId,
              let implSession = chatManager.sessions.first(where: { $0.id == implSessionId }) else {
            throw AutonomousFlowError.noChangesExtracted
        }

        let implContent = lastAssistantMessage(in: implSession)
        let fileChanges = CodeBlockParser.extractFileChanges(from: implContent)
        guard !fileChanges.isEmpty else {
            throw AutonomousFlowError.noChangesExtracted
        }

        let changeSet = ChangeSet(
            ticketKey: ticket.key,
            description: "Autonomous flow changes for \(ticket.key)",
            changes: fileChanges,
            commitMessage: GitClient.commitMessage(ticketKey: ticket.key, description: ticket.fields.summary),
            branchName: run.createdBranch ?? ""
        )
        implSession.changeSets.append(changeSet)
        run.changeSetId = changeSet.id

        try await ChangeSetService.applyAllChanges(changeSet, basePath: repoPath)
        run.advanceTo(.committing, message: "Applied \(fileChanges.count) file(s)")
        persistRunState(run)

        try Task.checkCancellation()

        // STAGE 5: Commit
        try await ChangeSetService.commitChanges(changeSet, at: repoPath, gitClient: gitClient)
        run.advanceTo(.reviewing, message: "Changes committed")
        persistRunState(run)

        NotificationService.shared.notifyCommitDone(
            ticketKey: ticket.key,
            message: changeSet.commitMessage
        )

        try Task.checkCancellation()

        // STAGE 6: Review
        let baseBranch = run.createdBranch.map { _ in "HEAD~1" } ?? "HEAD~1"
        let diff = try await gitClient.diffBetween(baseBranch, "HEAD", at: repoPath)
        let reviewMessage = PromptBuilder.buildReviewWithVerdictSuffix(diff: diff, ticket: ticket)

        let reviewSession = try await chatManager.runSessionToCompletion(
            ticket: ticket,
            purpose: .review,
            additionalUserMessage: reviewMessage,
            timeout: chatStageTimeout
        )
        run.reviewSessionId = reviewSession.id

        let reviewContent = lastAssistantMessage(in: reviewSession)
        let verdict = PromptBuilder.parseReviewVerdict(from: reviewContent)

        // STAGE 6b: Rework (conditional, max 1)
        if verdict == .needsRework && run.canRework {
            run.reworkCount += 1
            run.advanceTo(.reworking, message: "Review flagged issues — reworking (attempt \(run.reworkCount))")
            persistRunState(run)

            try Task.checkCancellation()

            let reworkMessage = PromptBuilder.buildReworkWithReviewFeedback(feedback: reviewContent)
            let reworkSession = try await chatManager.runSessionToCompletion(
                ticket: ticket,
                purpose: .implement,
                additionalUserMessage: reworkMessage,
                timeout: chatStageTimeout
            )
            run.reworkSessionId = reworkSession.id

            // Re-extract, re-apply, re-commit
            let reworkContent = lastAssistantMessage(in: reworkSession)
            let reworkChanges = CodeBlockParser.extractFileChanges(from: reworkContent)

            if !reworkChanges.isEmpty {
                let reworkChangeSet = ChangeSet(
                    ticketKey: ticket.key,
                    description: "Rework changes for \(ticket.key)",
                    changes: reworkChanges,
                    commitMessage: "\(ticket.key): Address review feedback",
                    branchName: run.createdBranch ?? ""
                )
                reworkSession.changeSets.append(reworkChangeSet)

                try await ChangeSetService.applyAllChanges(reworkChangeSet, basePath: repoPath)
                try await ChangeSetService.commitChanges(reworkChangeSet, at: repoPath, gitClient: gitClient)
            }

            // Re-review (result doesn't block — proceed either way)
            let reworkDiff = try await gitClient.diffBetween(baseBranch, "HEAD", at: repoPath)
            let reworkReviewMsg = PromptBuilder.buildReviewWithVerdictSuffix(diff: reworkDiff, ticket: ticket)
            let reReviewSession = try await chatManager.runSessionToCompletion(
                ticket: ticket,
                purpose: .review,
                additionalUserMessage: reworkReviewMsg,
                timeout: chatStageTimeout
            )
            run.reviewSessionId = reReviewSession.id
        }

        run.advanceTo(.pushing, message: "Review complete")
        persistRunState(run)

        try Task.checkCancellation()

        // STAGE 7: Push
        try await gitClient.push(at: repoPath, setUpstream: true)
        run.advanceTo(.creatingPR, message: "Pushed to remote")
        persistRunState(run)

        try Task.checkCancellation()

        // STAGE 8: Create PR
        let prTitle = GitClient.commitMessage(ticketKey: ticket.key, description: ticket.fields.summary)
        let changeSummary = fileChanges.map { "- \($0.changeType.displayName): `\($0.filePath)`" }.joined(separator: "\n")
        let prBody = GitHubService.buildPRBody(
            ticketKey: ticket.key,
            summary: ticket.fields.summary,
            changeSummary: changeSummary,
            jiraBaseURL: appState.jiraBaseURL
        )

        // Include review notes in PR body if review had concerns
        let finalPrBody: String
        if verdict == .needsRework {
            finalPrBody = prBody + "\n\n## Review Notes\n" + reviewContent.suffix(2000)
        } else {
            finalPrBody = prBody
        }

        let config = PRPipelineConfig(
            prTitle: prTitle,
            prBody: finalPrBody,
            transitionJira: true,
            targetJiraStatus: "In Review",
            addJiraComment: true
        )

        let result = try await PRPipelineService.executePRPipeline(
            ticket: ticket,
            config: config,
            repoPath: repoPath,
            gitClient: gitClient,
            githubService: appState.githubService,
            jiraService: appState.jiraService
        )

        run.createdPR = result.pullRequest
        for entry in result.stepLog {
            run.stageLog.append(StageLogEntry(stage: .creatingPR, message: entry))
        }

        // STAGE 9: JIRA update is handled by PRPipelineService above
        run.advanceTo(.updatingJira, message: "PR #\(result.pullRequest.number) created")
        persistRunState(run)

        // STAGE 10: Done
        run.advanceTo(.done, message: "Autonomous flow complete!")
        persistRunState(run)
        finalizeRun(run)

        NotificationService.shared.notifyAutonomousFlowComplete(
            ticketKey: ticket.key,
            prNumber: result.pullRequest.number,
            prURL: result.pullRequest.htmlUrl
        )
    }

    // MARK: - Pre-flight Checks

    private func preflightChecks(repoPath: String, gitClient: GitClient) async throws {
        // Verify git repo
        let isRepo = try await gitClient.isGitRepository(at: repoPath)
        guard isRepo else {
            throw AutonomousFlowError.preflightFailed("'\(repoPath)' is not a git repository")
        }

        // Check for clean working tree
        let status = try await gitClient.status(at: repoPath)
        guard status.isEmpty else {
            let dirtyFiles = status.prefix(5).map(\.path).joined(separator: ", ")
            throw AutonomousFlowError.preflightFailed(
                "Working tree is dirty (\(status.count) file(s): \(dirtyFiles)). Commit or stash changes first."
            )
        }

        // Verify remote URL is parseable
        let remoteURL = try await gitClient.remoteURL(at: repoPath)
        guard GitHubService.parseRemoteURL(remoteURL) != nil else {
            throw AutonomousFlowError.preflightFailed("Cannot parse remote URL: \(remoteURL)")
        }
    }

    // MARK: - Helpers

    private func lastAssistantMessage(in session: ChatSession) -> String {
        session.messages.last(where: { $0.role == .assistant })?.content ?? ""
    }

    private func finalizeRun(_ run: AutonomousFlowRun) {
        if activeRun?.id == run.id {
            completedRuns.insert(run, at: 0)
            activeRun = nil
        }
        pipelineTask = nil
    }

    // MARK: - Persistence

    private func persistRunState(_ run: AutonomousFlowRun) {
        guard let container = appState.modelContainer else { return }
        let context = ModelContext(container)

        // Try to find existing persisted run
        let runId = run.id
        var descriptor = FetchDescriptor<PersistentAutonomousFlowRun>(
            predicate: #Predicate { $0.runId == runId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            // Update existing
            existing.stageRaw = run.stage.rawValue
            existing.stageLogData = try? JSONEncoder().encode(run.stageLog)
            existing.planSessionId = run.planSessionId
            existing.implementSessionId = run.implementSessionId
            existing.reviewSessionId = run.reviewSessionId
            existing.reworkSessionId = run.reworkSessionId
            existing.changeSetId = run.changeSetId
            existing.createdBranch = run.createdBranch
            existing.errorMessage = run.errorMessage
            existing.reworkCount = run.reworkCount
            existing.completedAt = run.completedAt
        } else {
            // Insert new
            let persistent = PersistentAutonomousFlowRun(from: run)
            context.insert(persistent)
        }

        try? context.save()
    }
}
