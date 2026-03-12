import SwiftUI

/// Displays the progress of an autonomous flow run with stage dots,
/// current status, scrollable log, linked sessions, and control buttons.
struct AutonomousFlowProgressView: View {
    @Environment(AppState.self) private var appState
    let run: AutonomousFlowRun

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stage progress dots
            stageDotsRow

            // Current stage label + spinner
            currentStageRow

            Divider()

            // Stage log
            stageLogView

            // Linked sessions
            if !run.linkedSessionIds.isEmpty {
                linkedSessionsRow
            }

            // Error message
            if let error = run.errorMessage, run.stage == .failed {
                errorRow(error)
            }

            Divider()

            // Control buttons
            controlButtons
        }
        .padding(12)
        .background(.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Stage Dots

    private var stageDotsRow: some View {
        HStack(spacing: 4) {
            ForEach(AutonomousFlowStage.pipelineStages, id: \.self) { stage in
                stageDot(for: stage)
            }
        }
    }

    private func stageDot(for stage: AutonomousFlowStage) -> some View {
        let isDone = isStageComplete(stage)
        let isCurrent = isCurrentStage(stage)

        return Circle()
            .fill(isDone ? Color.green : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.3)))
            .frame(width: 8, height: 8)
            .overlay {
                if isCurrent && run.isRunning {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .frame(width: 12, height: 12)
                }
            }
            .help(stage.displayName)
    }

    private func isStageComplete(_ stage: AutonomousFlowStage) -> Bool {
        let pipelineStages = AutonomousFlowStage.pipelineStages
        guard let currentIdx = pipelineStages.firstIndex(of: mapToNearestPipeline(run.stage)),
              let checkIdx = pipelineStages.firstIndex(of: stage) else { return false }
        return checkIdx < currentIdx
    }

    private func isCurrentStage(_ stage: AutonomousFlowStage) -> Bool {
        mapToNearestPipeline(run.stage) == stage
    }

    /// Map approval/rework stages to their nearest pipeline stage for display.
    private func mapToNearestPipeline(_ stage: AutonomousFlowStage) -> AutonomousFlowStage {
        switch stage {
        case .awaitingPlanApproval: return .planning
        case .awaitingImplApproval: return .implementing
        case .reworking: return .reviewing
        case .failed, .cancelled: return run.stageLog.last.map { mapToNearestPipeline($0.stage) } ?? .creatingBranch
        default: return stage
        }
    }

    // MARK: - Current Stage

    private var currentStageRow: some View {
        HStack(spacing: 8) {
            if run.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: run.stage.icon)
                    .foregroundStyle(stageColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(run.stage.displayName)
                    .font(.headline)
                    .foregroundStyle(stageColor)

                Text(run.ticketKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if run.stage == .done, let pr = run.createdPR {
                if let prURL = URL(string: pr.htmlUrl) {
                    Link(destination: prURL) {
                        Label("PR #\(pr.number)", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var stageColor: Color {
        switch run.stage {
        case .done: .green
        case .failed: .red
        case .cancelled: .secondary
        case .awaitingPlanApproval, .awaitingImplApproval: .orange
        default: .accentColor
        }
    }

    // MARK: - Stage Log

    private var stageLogView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(run.stageLog) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.stage.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)

                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxHeight: 150)
    }

    // MARK: - Linked Sessions

    private var linkedSessionsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Chat Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let id = run.planSessionId {
                    sessionLink(id: id, label: "Plan", icon: "brain", color: .blue)
                }
                if let id = run.implementSessionId {
                    sessionLink(id: id, label: "Implement", icon: "hammer", color: .orange)
                }
                if let id = run.reviewSessionId {
                    sessionLink(id: id, label: "Review", icon: "eye", color: .green)
                }
                if let id = run.reworkSessionId {
                    sessionLink(id: id, label: "Rework", icon: "arrow.counterclockwise", color: .purple)
                }
            }
        }
    }

    private func sessionLink(id: UUID, label: String, icon: String, color: Color) -> some View {
        Button {
            appState.chatManager.switchTo(sessionId: id)
        } label: {
            Label(label, systemImage: icon)
                .font(.caption2)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .controlSize(.mini)
    }

    // MARK: - Error

    private func errorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
        .padding(8)
        .background(.red.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 8) {
            if run.isPaused {
                Button {
                    appState.autonomousFlowOrchestrator.approveAndContinue()
                } label: {
                    Label("Approve & Continue", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
            }

            if run.stage == .failed {
                Button {
                    appState.autonomousFlowOrchestrator.retryFailedStage()
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if run.isRunning || run.isPaused {
                Spacer()

                Button {
                    appState.autonomousFlowOrchestrator.cancelRun()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
    }
}
