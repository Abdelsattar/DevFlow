import SwiftUI

/// Displays a ChangeSet for review — shows each file change with its path,
/// change type, syntax-highlighted content, and apply/reject controls.
/// Also provides commit controls once all changes have been reviewed.
struct DiffPreviewView: View {
    @Environment(AppState.self) private var appState
    let changeSet: ChangeSet
    let session: ChatSession
    let ticket: JiraTicket?

    @State private var expandedFileIds: Set<UUID> = []
    @State private var isCommitting: Bool = false
    @State private var commitError: String?
    @State private var commitSuccess: Bool = false
    @State private var showPRCreation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(changeSet.changes) { change in
                        FileChangeCard(
                            change: change,
                            isExpanded: expandedFileIds.contains(change.id),
                            onToggleExpand: { toggleExpanded(change) },
                            onApply: { applyChange(change) },
                            onReject: { rejectChange(change) }
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            commitFooter
        }
        .sheet(isPresented: $showPRCreation) {
            if let ticket {
                PRCreationView(ticket: ticket, changeSet: changeSet)
                    .environment(appState)
                    .frame(minWidth: 550, minHeight: 500)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Code Changes")
                    .font(.headline)

                Text("\(changeSet.changes.count) file(s) — \(changeSet.pendingCount) pending, \(changeSet.appliedCount) applied, \(changeSet.rejectedCount) rejected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Apply all / Reject all buttons
            if changeSet.pendingCount > 0 {
                Button("Apply All") {
                    applyAllChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button("Reject All") {
                    rejectAllChanges()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Commit Footer

    private var commitFooter: some View {
        VStack(spacing: 8) {
            if let error = commitError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { commitError = nil }
                        .buttonStyle(.plain)
                        .font(.caption2)
                }
                .padding(.horizontal, 16)
            }

            if commitSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Changes committed successfully!")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()

                    if ticket != nil {
                        Button {
                            showPRCreation = true
                        } label: {
                            Label("Create PR", systemImage: "arrow.triangle.pull")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 12) {
                // Branch name
                VStack(alignment: .leading, spacing: 2) {
                    Text("Branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(changeSet.branchName.isEmpty ? "current branch" : changeSet.branchName)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }

                Divider()
                    .frame(height: 30)

                // Commit message (editable)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commit Message")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    @Bindable var cs = changeSet
                    TextField("Enter commit message...", text: $cs.commitMessage)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .fontDesign(.monospaced)
                }

                // Commit button
                Button {
                    Task { await commitChanges() }
                } label: {
                    HStack(spacing: 4) {
                        if isCommitting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("Commit")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canCommit)
                .accessibilityLabel(isCommitting ? "Committing changes" : "Commit changes")
                .accessibilityHint("Commit \(changeSet.appliedCount) applied file changes")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: - Computed

    private var canCommit: Bool {
        changeSet.hasAppliedChanges
        && !changeSet.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isCommitting
        && !changeSet.isCommitted
    }

    // MARK: - Actions

    private func toggleExpanded(_ change: FileChange) {
        if expandedFileIds.contains(change.id) {
            expandedFileIds.remove(change.id)
        } else {
            expandedFileIds.insert(change.id)
        }
    }

    private func applyChange(_ change: FileChange) {
        Task {
            do {
                try await ChangeSetService.applyChange(change, basePath: appState.workspacePath)
            } catch {
                change.applyError = error.localizedDescription
            }
        }
    }

    private func rejectChange(_ change: FileChange) {
        change.isRejected = true
        change.isApplied = false
        change.applyError = nil
    }

    private func applyAllChanges() {
        Task {
            for change in changeSet.changes where change.isPending {
                do {
                    try await ChangeSetService.applyChange(change, basePath: appState.workspacePath)
                } catch {
                    change.applyError = error.localizedDescription
                }
            }
        }
    }

    private func rejectAllChanges() {
        for change in changeSet.changes where change.isPending {
            rejectChange(change)
        }
    }

    private func commitChanges() async {
        isCommitting = true
        commitError = nil

        do {
            try await ChangeSetService.commitChanges(
                changeSet,
                at: appState.workspacePath,
                gitClient: appState.gitClient
            )
            commitSuccess = true

            let ticketKey = ticket?.key ?? "Unknown"
            NotificationService.shared.notifyCommitDone(
                ticketKey: ticketKey,
                message: changeSet.commitMessage
            )
        } catch {
            commitError = error.localizedDescription
            NotificationService.shared.notifyError(
                title: "Commit Failed",
                message: error.localizedDescription
            )
        }

        isCommitting = false
    }
}

// MARK: - File Change Card

/// A card displaying a single file change with expand/collapse, content preview,
/// and apply/reject buttons.
struct FileChangeCard: View {
    let change: FileChange
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onApply: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header row
            fileHeader

            if isExpanded {
                Divider()

                // Code content
                codeContent
            }
        }
        .background(cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: - File Header

    private var fileHeader: some View {
        HStack(spacing: 8) {
            // Expand/collapse chevron
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse file" : "Expand file")
            .accessibilityHint("Toggle code preview for \(change.filePath)")

            // Change type badge
            changeTypeBadge

            // File path
            VStack(alignment: .leading, spacing: 1) {
                Text(change.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .fontDesign(.monospaced)
                    .lineLimit(1)

                Text(change.directory)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
            }

            Spacer()

            // Line count
            Text("\(change.lineCount) lines")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Status indicator
            statusIndicator

            // Apply/Reject buttons (only if pending)
            if change.isPending {
                Button("Apply") { onApply() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.mini)
                    .accessibilityLabel("Apply change")
                    .accessibilityHint("Write \(change.filePath) to disk")

                Button("Reject") { onReject() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Reject change")
                    .accessibilityHint("Skip \(change.filePath)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }
    }

    // MARK: - Code Content

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(change.content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 400)
        .background(Color.black.opacity(0.03))
    }

    // MARK: - Subviews

    private var changeTypeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: change.changeType.icon)
                .font(.caption2)
            Text(change.changeType.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(changeTypeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(changeTypeColor.opacity(0.12))
        .cornerRadius(4)
    }

    private var statusIndicator: some View {
        Group {
            if change.isApplied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .accessibilityLabel("Applied")
            } else if change.isRejected {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityLabel("Rejected")
            } else if let error = change.applyError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help(error)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }

    // MARK: - Styling

    private var changeTypeColor: Color {
        switch change.changeType {
        case .create: .green
        case .modify: .blue
        case .delete: .red
        }
    }

    private var cardBackground: Color {
        if change.isApplied {
            Color.green.opacity(0.04)
        } else if change.isRejected {
            Color.red.opacity(0.04)
        } else {
            Color.secondary.opacity(0.04)
        }
    }

    private var borderColor: Color {
        if change.isApplied {
            Color.green.opacity(0.3)
        } else if change.isRejected {
            Color.red.opacity(0.2)
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}
