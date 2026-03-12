import Foundation

// MARK: - Autonomous Flow Stage

/// Ordered stages in an autonomous flow run.
enum AutonomousFlowStage: String, Codable, Sendable, CaseIterable {
    case idle
    case creatingBranch
    case planning
    case awaitingPlanApproval
    case implementing
    case awaitingImplApproval
    case applyingChanges
    case committing
    case reviewing
    case reworking
    case pushing
    case creatingPR
    case updatingJira
    case done
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .idle:                  return "Idle"
        case .creatingBranch:        return "Creating Branch"
        case .planning:              return "Planning"
        case .awaitingPlanApproval:  return "Awaiting Plan Approval"
        case .implementing:          return "Implementing"
        case .awaitingImplApproval:  return "Awaiting Impl Approval"
        case .applyingChanges:       return "Applying Changes"
        case .committing:            return "Committing"
        case .reviewing:             return "Reviewing"
        case .reworking:             return "Reworking"
        case .pushing:               return "Pushing"
        case .creatingPR:            return "Creating PR"
        case .updatingJira:          return "Updating JIRA"
        case .done:                  return "Done"
        case .failed:                return "Failed"
        case .cancelled:             return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .idle:                  return "circle"
        case .creatingBranch:        return "arrow.triangle.branch"
        case .planning:              return "brain"
        case .awaitingPlanApproval:  return "hand.raised"
        case .implementing:          return "hammer"
        case .awaitingImplApproval:  return "hand.raised.fill"
        case .applyingChanges:       return "doc.on.doc"
        case .committing:            return "checkmark.circle"
        case .reviewing:             return "eye"
        case .reworking:             return "arrow.counterclockwise"
        case .pushing:               return "arrow.up.circle"
        case .creatingPR:            return "arrow.triangle.pull"
        case .updatingJira:          return "ticket"
        case .done:                  return "checkmark.seal.fill"
        case .failed:                return "xmark.circle.fill"
        case .cancelled:             return "stop.circle.fill"
        }
    }

    /// Whether this stage represents an active (in-progress) state.
    var isActive: Bool {
        switch self {
        case .creatingBranch, .planning, .implementing, .applyingChanges,
             .committing, .reviewing, .reworking, .pushing, .creatingPR, .updatingJira:
            return true
        default:
            return false
        }
    }

    /// Whether this stage is a pause point awaiting user approval.
    var isAwaitingApproval: Bool {
        self == .awaitingPlanApproval || self == .awaitingImplApproval
    }

    /// Whether this stage represents a terminal state.
    var isTerminal: Bool {
        self == .done || self == .failed || self == .cancelled
    }

    /// The ordered pipeline stages (excluding terminal/pause states) for progress display.
    static var pipelineStages: [AutonomousFlowStage] {
        [.creatingBranch, .planning, .implementing, .applyingChanges,
         .committing, .reviewing, .pushing, .creatingPR, .updatingJira, .done]
    }
}

// MARK: - Approval Mode

/// Controls where the autonomous flow pauses for user approval.
enum AutonomousFlowApprovalMode: String, Codable, Sendable {
    case fullyAutonomous
    case approveAfterPlan
    case approveAfterBoth

    var displayName: String {
        switch self {
        case .fullyAutonomous: return "Fully Autonomous"
        case .approveAfterPlan: return "Approve After Plan"
        case .approveAfterBoth: return "Approve After Plan & Impl"
        }
    }

    var description: String {
        switch self {
        case .fullyAutonomous:
            return "Runs the entire pipeline without pausing. PR is the human checkpoint."
        case .approveAfterPlan:
            return "Pauses after AI generates the plan, then runs the rest automatically."
        case .approveAfterBoth:
            return "Pauses after both plan and implementation for review before proceeding."
        }
    }
}

// MARK: - Review Verdict

/// The AI reviewer's verdict on the implementation.
enum ReviewVerdict: String, Codable, Sendable {
    case approved
    case needsRework

    var displayName: String {
        switch self {
        case .approved: return "Approved"
        case .needsRework: return "Needs Rework"
        }
    }
}

// MARK: - Stage Log Entry

/// A single log entry for a completed stage in an autonomous flow run.
struct StageLogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let stage: AutonomousFlowStage
    let message: String
    let timestamp: Date

    init(stage: AutonomousFlowStage, message: String) {
        self.id = UUID()
        self.stage = stage
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - Autonomous Flow Run

/// Observable model tracking the state of a single autonomous flow execution.
/// Each run is tied to a ticket and progresses through the pipeline stages.
@MainActor
@Observable
final class AutonomousFlowRun: Identifiable {
    let id: UUID
    let ticketKey: String
    let ticketSummary: String
    var stage: AutonomousFlowStage
    let approvalMode: AutonomousFlowApprovalMode
    var stageLog: [StageLogEntry]
    var planSessionId: UUID?
    var implementSessionId: UUID?
    var reviewSessionId: UUID?
    var reworkSessionId: UUID?
    var changeSetId: UUID?
    var createdBranch: String?
    var createdPR: GitHubPullRequest?
    var errorMessage: String?
    var reworkCount: Int
    let startedAt: Date
    var completedAt: Date?

    /// Maximum rework cycles before proceeding anyway.
    static let maxReworkCycles = 1

    init(
        id: UUID = UUID(),
        ticketKey: String,
        ticketSummary: String,
        approvalMode: AutonomousFlowApprovalMode = .fullyAutonomous,
        stage: AutonomousFlowStage = .idle,
        stageLog: [StageLogEntry] = [],
        reworkCount: Int = 0
    ) {
        self.id = id
        self.ticketKey = ticketKey
        self.ticketSummary = ticketSummary
        self.approvalMode = approvalMode
        self.stage = stage
        self.stageLog = stageLog
        self.reworkCount = reworkCount
        self.startedAt = Date()
    }

    // MARK: - Computed

    /// Whether the run is actively executing (not paused or terminal).
    var isRunning: Bool {
        stage.isActive
    }

    /// Whether the run is paused at an approval gate.
    var isPaused: Bool {
        stage.isAwaitingApproval
    }

    /// Whether the run has finished (done, failed, or cancelled).
    var isFinished: Bool {
        stage.isTerminal
    }

    /// Whether rework is still allowed.
    var canRework: Bool {
        reworkCount < Self.maxReworkCycles
    }

    /// All linked session IDs for navigating to chat views.
    var linkedSessionIds: [UUID] {
        [planSessionId, implementSessionId, reviewSessionId, reworkSessionId].compactMap { $0 }
    }

    // MARK: - State Mutations

    func advanceTo(_ newStage: AutonomousFlowStage, message: String) {
        stage = newStage
        stageLog.append(StageLogEntry(stage: newStage, message: message))
        if newStage.isTerminal {
            completedAt = Date()
        }
    }

    func fail(message: String) {
        errorMessage = message
        advanceTo(.failed, message: "Failed: \(message)")
    }

    func cancel() {
        advanceTo(.cancelled, message: "Cancelled by user")
    }
}
