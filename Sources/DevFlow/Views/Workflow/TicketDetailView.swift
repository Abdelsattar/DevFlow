import SwiftUI

struct TicketDetailView: View {
    let ticket: JiraTicket
    @Environment(AppState.self) private var appState
    @State private var showPRCreation: Bool = false
    @State private var prChangeSet: ChangeSet?
    @State private var autonomousApprovalMode: AutonomousFlowApprovalMode = .approveAfterPlan
    @State private var autonomousFlowError: String?
    @State private var isAutonomousModeEnabled: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Workflow Buttons (always visible)
                workflowSection

                // Active chats for this ticket
                ticketChatsSection

                // Show "Create PR" if there's a committed change set
                committedChangesSection

                // Autonomous Mode toggle + content
                autonomousModeSection

                Divider()

                // Description
                descriptionSection

                // Comments
                if let commentContainer = ticket.fields.comment,
                   !commentContainer.comments.isEmpty {
                    Divider()
                    commentsSection(commentContainer.comments)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showPRCreation) {
            if let changeSet = prChangeSet {
                PRCreationView(ticket: ticket, changeSet: changeSet)
                    .environment(appState)
                    .frame(minWidth: 550, minHeight: 500)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ticket.key)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)

                Spacer()

                statusBadge(ticket.fields.status)
            }

            Text(ticket.fields.summary)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                if let priority = ticket.fields.priority {
                    Label(priority.name, systemImage: priority.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let issueType = ticket.fields.issuetype {
                    Label(issueType.name, systemImage: issueType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let assignee = ticket.fields.assignee {
                    Label(assignee.displayName, systemImage: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !ticket.fields.components.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(ticket.fields.components) { component in
                        Text(component.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12))
                            .foregroundStyle(.primary)
                            .cornerRadius(4)
                            .accessibilityLabel("Component: \(component.name)")
                    }
                }
            }
        }
    }

    // MARK: - Workflow Section

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workflow")
                .font(.headline)

            Text("Each action opens a new AI chat session for this ticket.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                workflowButton(
                    title: "Plan",
                    icon: "doc.text.magnifyingglass",
                    purpose: .plan,
                    help: "Start an AI chat to plan the implementation"
                )

                workflowButton(
                    title: "Implement",
                    icon: "hammer",
                    purpose: .implement,
                    help: "Start an AI chat to implement the changes"
                )

                workflowButton(
                    title: "Review",
                    icon: "checkmark.shield",
                    purpose: .review,
                    help: "Start an AI chat to review the implementation"
                )
            }

            // General chat
            Button {
                appState.chatManager.createSession(ticket: ticket, purpose: .general)
            } label: {
                Label("Open General Chat", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .help("Start a free-form AI chat about this ticket")
        }
    }

    private func workflowButton(title: String, icon: String, purpose: ChatPurpose, help: String) -> some View {
        Button {
            appState.chatManager.createSession(ticket: ticket, purpose: purpose)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .help(help)
        .accessibilityLabel("\(title) workflow")
        .accessibilityHint("Opens a new AI chat to \(title.lowercased()) for \(ticket.key)")
    }

    // MARK: - Ticket Chats Section

    private var ticketChatsSection: some View {
        let ticketSessions = appState.chatManager.sessions(for: ticket.key)

        return Group {
            if !ticketSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Chats")
                        .font(.headline)

                    ForEach(ticketSessions) { session in
                        chatSessionRow(session)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Chats")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No chats yet")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Start a workflow above to open an AI chat session for this ticket.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func chatSessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.purpose.icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.purpose.displayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    if !session.changeSets.isEmpty {
                        Text("\(session.changeSets.count) change set(s)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .cornerRadius(3)
                    }
                }

                if let preview = session.lastMessagePreview {
                    Text(preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if session.isGenerating {
                ProgressView()
                    .controlSize(.mini)
            }

            Text("\(session.messages.count - 1) msgs")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                appState.chatManager.switchTo(session: session)
            } label: {
                Text("Open")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Committed Changes Section

    private var committedChangesSection: some View {
        let ticketSessions = appState.chatManager.sessions(for: ticket.key)
        let committedSets = ticketSessions.flatMap { $0.changeSets.filter(\.isCommitted) }

        return Group {
            if !committedSets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text("Ready for PR")
                        .font(.headline)

                    Text("These change sets have been committed and are ready to push.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(committedSets) { changeSet in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(changeSet.commitMessage)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)

                                Text("\(changeSet.appliedCount) file(s) committed")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                prChangeSet = changeSet
                                showPRCreation = true
                            } label: {
                                Label("Create PR", systemImage: "arrow.triangle.pull")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Autonomous Mode Section

    private var autonomousModeSection: some View {
        let orchestrator = appState.autonomousFlowOrchestrator
        let activeRun = orchestrator.activeRun
        let hasActiveRunForTicket = activeRun?.ticketKey == ticket.key

        return VStack(alignment: .leading, spacing: 12) {
            Divider()

            // Toggle header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Autonomous Mode")
                        .font(.headline)

                    Text("Run the full pipeline automatically: plan, implement, review, and create a PR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Show toggle only when no active run is in progress for this ticket
                if !hasActiveRunForTicket || activeRun == nil {
                    Toggle("", isOn: $isAutonomousModeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }

            // Autonomous content (shown when toggled on or when a run is active for this ticket)
            if isAutonomousModeEnabled || hasActiveRunForTicket {
                autonomousFlowContent(
                    orchestrator: orchestrator,
                    activeRun: activeRun,
                    hasActiveRunForTicket: hasActiveRunForTicket
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isAutonomousModeEnabled)
        .onChange(of: hasActiveRunForTicket) { _, isActive in
            // Auto-enable the toggle when a run becomes active for this ticket
            if isActive {
                isAutonomousModeEnabled = true
            }
        }
    }

    @ViewBuilder
    private func autonomousFlowContent(
        orchestrator: AutonomousFlowOrchestrator,
        activeRun: AutonomousFlowRun?,
        hasActiveRunForTicket: Bool
    ) -> some View {
        if let run = activeRun, hasActiveRunForTicket {
            // Show progress for this ticket's run
            AutonomousFlowProgressView(run: run)
        } else if activeRun != nil {
            // Another ticket's run is active
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Another autonomous flow is already running (\(activeRun?.ticketKey ?? "")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            // No active run — show start controls
            VStack(alignment: .leading, spacing: 10) {
                Picker("Approval Mode", selection: $autonomousApprovalMode) {
                    ForEach([AutonomousFlowApprovalMode.fullyAutonomous,
                             .approveAfterPlan, .approveAfterBoth], id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help(autonomousApprovalMode.description)

                Button {
                    startAutonomousFlow()
                } label: {
                    Label("Start Autonomous Flow", systemImage: "bolt.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.regular)
            }

            if let error = autonomousFlowError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { autonomousFlowError = nil }
                        .buttonStyle(.plain)
                        .font(.caption2)
                }
            }
        }

        // Show recent completed runs for this ticket
        let ticketRuns = orchestrator.completedRuns.filter { $0.ticketKey == ticket.key }
        if !ticketRuns.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(ticketRuns.prefix(3)) { run in
                    HStack(spacing: 6) {
                        Image(systemName: run.stage.icon)
                            .font(.caption2)
                            .foregroundStyle(run.stage == .done ? .green : .red)
                        Text(run.stage.displayName)
                            .font(.caption)
                        Spacer()
                        Text(run.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func startAutonomousFlow() {
        autonomousFlowError = nil
        do {
            try appState.autonomousFlowOrchestrator.startRun(
                ticket: ticket,
                approvalMode: autonomousApprovalMode
            )
        } catch {
            autonomousFlowError = error.localizedDescription
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)

            Text(ticket.fields.plainTextDescription)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.secondary.opacity(0.05))
                .cornerRadius(8)
        }
    }

    // MARK: - Comments

    private func commentsSection(_ comments: [JiraComment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comments (\(comments.count))")
                .font(.headline)

            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.author?.displayName ?? "Unknown")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Spacer()

                        if let created = comment.created {
                            Text(DateFormatting.relativeDate(from: created))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(comment.plainTextBody)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(.secondary.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: JiraStatus) -> some View {
        Text(status.name)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .cornerRadius(6)
            .accessibilityLabel("Status: \(status.name)")
    }

    private func statusColor(_ status: JiraStatus) -> Color {
        switch status.color {
        case .gray:   return .secondary
        case .blue:   return .accentColor
        case .orange: return .orange
        case .green:  return .green
        }
    }
}
