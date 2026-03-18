import Foundation
import Testing
@testable import DevFlow

// MARK: - Autonomous Flow Tests

@Suite("Autonomous Flow Tests")
struct AutonomousFlowTests {

    // MARK: - Helpers

    private func makeSampleTicket(
        key: String = "PLAT-456",
        summary: String = "Add autonomous flow feature"
    ) -> JiraTicket {
        JiraTicket(
            id: "20001",
            key: key,
            fields: JiraIssueFields(
                summary: summary,
                description: nil,
                status: JiraStatus(id: "1", name: "To Do", iconUrl: nil),
                priority: JiraPriority(id: "3", name: "Medium", iconUrl: nil),
                assignee: nil,
                components: [],
                comment: nil,
                issuetype: JiraIssueType(id: "10001", name: "Story", iconUrl: nil)
            )
        )
    }

    // MARK: - Stage Enum Tests

    @Test("Stage display names are non-empty")
    func stageDisplayNames() {
        for stage in AutonomousFlowStage.allCases {
            #expect(!stage.displayName.isEmpty, "Stage \(stage.rawValue) has empty display name")
        }
    }

    @Test("Stage icons are non-empty")
    func stageIcons() {
        for stage in AutonomousFlowStage.allCases {
            #expect(!stage.icon.isEmpty, "Stage \(stage.rawValue) has empty icon")
        }
    }

    @Test("Terminal stages are correctly identified")
    func terminalStages() {
        #expect(AutonomousFlowStage.done.isTerminal)
        #expect(AutonomousFlowStage.failed.isTerminal)
        #expect(AutonomousFlowStage.cancelled.isTerminal)
        #expect(!AutonomousFlowStage.planning.isTerminal)
        #expect(!AutonomousFlowStage.idle.isTerminal)
    }

    @Test("Active stages are correctly identified")
    func activeStages() {
        #expect(AutonomousFlowStage.planning.isActive)
        #expect(AutonomousFlowStage.implementing.isActive)
        #expect(AutonomousFlowStage.reviewing.isActive)
        #expect(AutonomousFlowStage.pushing.isActive)
        #expect(!AutonomousFlowStage.idle.isActive)
        #expect(!AutonomousFlowStage.done.isActive)
        #expect(!AutonomousFlowStage.awaitingPlanApproval.isActive)
    }

    @Test("Approval stages are correctly identified")
    func approvalStages() {
        #expect(AutonomousFlowStage.awaitingPlanApproval.isAwaitingApproval)
        #expect(AutonomousFlowStage.awaitingImplApproval.isAwaitingApproval)
        #expect(!AutonomousFlowStage.planning.isAwaitingApproval)
        #expect(!AutonomousFlowStage.done.isAwaitingApproval)
    }

    @Test("Pipeline stages are in correct order")
    func pipelineStagesOrder() {
        let stages = AutonomousFlowStage.pipelineStages
        #expect(stages.first == .creatingBranch)
        #expect(stages.last == .done)
        #expect(stages.contains(.planning))
        #expect(stages.contains(.pushing))
        // Approval/rework stages are not in pipeline display
        #expect(!stages.contains(.awaitingPlanApproval))
        #expect(!stages.contains(.reworking))
    }

    // MARK: - Approval Mode Tests

    @Test("Approval mode display names are non-empty")
    func approvalModeDisplayNames() {
        let modes: [AutonomousFlowApprovalMode] = [.fullyAutonomous, .approveAfterPlan, .approveAfterBoth]
        for mode in modes {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.description.isEmpty)
        }
    }

    // MARK: - Review Verdict Parsing Tests

    @Test("Parse structured VERDICT: APPROVED")
    func parseVerdictApproved() {
        let text = """
        The implementation looks good. All ACs are met.
        
        VERDICT: APPROVED
        """
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .approved)
    }

    @Test("Parse structured VERDICT: NEEDS_REWORK")
    func parseVerdictNeedsRework() {
        let text = """
        There are several issues that need to be addressed.
        
        VERDICT: NEEDS_REWORK
        """
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .needsRework)
    }

    @Test("Parse verdict with keyword fallback — needs rework")
    func parseVerdictKeywordRework() {
        let text = "The implementation has a critical issue that must be fixed before merging."
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .needsRework)
    }

    @Test("Parse verdict with keyword fallback — blocking issue")
    func parseVerdictBlockingIssue() {
        let text = "This is a blocking issue — the API endpoint doesn't handle errors."
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .needsRework)
    }

    @Test("Parse verdict defaults to approved when ambiguous")
    func parseVerdictDefaultApproved() {
        let text = "The code looks reasonable, here are some minor suggestions."
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .approved)
    }

    @Test("Parse verdict is case insensitive")
    func parseVerdictCaseInsensitive() {
        let text = "verdict: needs_rework"
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .needsRework)
    }

    @Test("Parse verdict prefers structured over keywords")
    func parseVerdictStructuredOverKeywords() {
        // Text mentions "critical issue" (rework keyword) but verdict says APPROVED
        let text = """
        There was a critical issue but it was already addressed.
        
        VERDICT: APPROVED
        """
        #expect(PromptBuilder.parseReviewVerdict(from: text) == .approved)
    }

    // MARK: - AutonomousFlowRun State Tests

    @Test("Run starts in idle state")
    @MainActor
    func runInitialState() {
        let run = AutonomousFlowRun(
            ticketKey: "PLAT-456",
            ticketSummary: "Test run"
        )
        #expect(run.stage == .idle)
        #expect(!run.isRunning)
        #expect(!run.isPaused)
        #expect(!run.isFinished)
        #expect(run.reworkCount == 0)
        #expect(run.canRework)
        #expect(run.stageLog.isEmpty)
    }

    @Test("Run advances through stages correctly")
    @MainActor
    func runStageAdvancement() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-456", ticketSummary: "Test")

        run.advanceTo(.creatingBranch, message: "Creating branch...")
        #expect(run.stage == .creatingBranch)
        #expect(run.isRunning)
        #expect(run.stageLog.count == 1)

        run.advanceTo(.planning, message: "Planning...")
        #expect(run.stage == .planning)
        #expect(run.stageLog.count == 2)
    }

    @Test("Run fail sets terminal state")
    @MainActor
    func runFailState() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-456", ticketSummary: "Test")
        run.advanceTo(.planning, message: "Planning...")
        run.fail(message: "Something went wrong")

        #expect(run.stage == .failed)
        #expect(run.isFinished)
        #expect(run.errorMessage == "Something went wrong")
        #expect(run.completedAt != nil)
    }

    @Test("Run cancel sets terminal state")
    @MainActor
    func runCancelState() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-456", ticketSummary: "Test")
        run.advanceTo(.implementing, message: "Implementing...")
        run.cancel()

        #expect(run.stage == .cancelled)
        #expect(run.isFinished)
        #expect(run.completedAt != nil)
    }

    @Test("Run rework is capped at max cycles")
    @MainActor
    func runReworkCap() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-456", ticketSummary: "Test")
        #expect(run.canRework)

        run.reworkCount = 1
        #expect(!run.canRework)
    }

    @Test("Run linked session IDs are collected correctly")
    @MainActor
    func runLinkedSessions() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-456", ticketSummary: "Test")
        #expect(run.linkedSessionIds.isEmpty)

        let planId = UUID()
        let implId = UUID()
        run.planSessionId = planId
        run.implementSessionId = implId
        #expect(run.linkedSessionIds.count == 2)
        #expect(run.linkedSessionIds.contains(planId))
        #expect(run.linkedSessionIds.contains(implId))
    }

    // MARK: - Approval Gate Tests

    @Test("Approval gate pause/resume for plan approval mode")
    @MainActor
    func approvalGatePlanPause() {
        let run = AutonomousFlowRun(
            ticketKey: "PLAT-456",
            ticketSummary: "Test",
            approvalMode: .approveAfterPlan
        )

        run.advanceTo(.awaitingPlanApproval, message: "Awaiting plan approval")
        #expect(run.isPaused)
        #expect(!run.isRunning)
        #expect(!run.isFinished)
    }

    @Test("Approval gate pause/resume for both approval mode")
    @MainActor
    func approvalGateBothPause() {
        let run = AutonomousFlowRun(
            ticketKey: "PLAT-456",
            ticketSummary: "Test",
            approvalMode: .approveAfterBoth
        )

        run.advanceTo(.awaitingImplApproval, message: "Awaiting impl approval")
        #expect(run.isPaused)
    }

    // MARK: - PromptBuilder Context Tests

    @Test("buildImplementWithPlanContext includes plan content")
    func implementWithPlanContext() {
        let plan = "1. Create models\n2. Add services"
        let result = PromptBuilder.buildImplementWithPlanContext(plan: plan)
        #expect(result.contains("Create models"))
        #expect(result.contains("Add services"))
        #expect(result.contains("Plan"))
    }

    @Test("buildReworkWithReviewFeedback includes feedback")
    func reworkWithFeedback() {
        let feedback = "Missing error handling in the API call."
        let result = PromptBuilder.buildReworkWithReviewFeedback(feedback: feedback)
        #expect(result.contains("Missing error handling"))
        #expect(result.contains("Review Feedback"))
    }

    @Test("buildReviewWithVerdictSuffix includes verdict instruction")
    func reviewVerdictSuffix() {
        let ticket = makeSampleTicket()
        let result = PromptBuilder.buildReviewWithVerdictSuffix(diff: "+ some code", ticket: ticket)
        #expect(result.contains("VERDICT: APPROVED"))
        #expect(result.contains("VERDICT: NEEDS_REWORK"))
    }

    // MARK: - StageLogEntry Tests

    @Test("StageLogEntry has unique ID and timestamp")
    func stageLogEntry() {
        let entry1 = StageLogEntry(stage: .planning, message: "Planning started")
        let entry2 = StageLogEntry(stage: .implementing, message: "Implementing started")
        #expect(entry1.id != entry2.id)
        #expect(entry1.stage == .planning)
        #expect(entry1.message == "Planning started")
    }

    // MARK: - Retry Skip-Stage Tests

    @Test("Run with createdBranch set is treated as retry — branch already exists")
    @MainActor
    func retryWithExistingBranch() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-789", ticketSummary: "Test retry")
        run.advanceTo(.planning, message: "Created branch")
        run.createdBranch = "PLAT-789-test-retry"
        run.fail(message: "AI timed out")

        // After failure, createdBranch is preserved
        #expect(run.createdBranch == "PLAT-789-test-retry")
        #expect(run.stage == .failed)
        // On retry the orchestrator will use run.createdBranch instead of creating a new one
        #expect(run.createdBranch != nil)
    }

    @Test("Run with implementSessionId set skips implement stage on retry")
    @MainActor
    func retrySkipsCompletedImplementStage() {
        let run = AutonomousFlowRun(ticketKey: "PLAT-789", ticketSummary: "Test retry")
        let implId = UUID()
        run.createdBranch = "PLAT-789-test-retry"
        run.planSessionId = UUID()
        run.implementSessionId = implId
        run.fail(message: "Push failed")

        // Both branch and implement session are preserved across failure
        #expect(run.implementSessionId == implId)
        #expect(run.createdBranch != nil)
    }
}
