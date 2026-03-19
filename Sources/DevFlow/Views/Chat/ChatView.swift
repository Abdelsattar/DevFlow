import SwiftUI

/// Displays a single chat conversation with message bubbles, an input field,
/// and change extraction/preview functionality for implement sessions.
@MainActor
struct ChatView: View {
    @Environment(AppState.self) private var appState
    let session: ChatSession

    @State private var inputText: String = ""
    @State private var isAtBottom: Bool = true
    @State private var showingDiffPreview: Bool = false
    @State private var activeChangeSet: ChangeSet?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            chatHeader

            Divider()

            // If there's an active ChangeSet being reviewed, show it
            if showingDiffPreview, let changeSet = activeChangeSet {
                DiffPreviewView(
                    changeSet: changeSet,
                    session: session,
                    ticket: appState.tickets.first(where: { $0.key == session.ticketKey })
                )
            } else {
                // Message list or empty state
                messageListOrEmptyState

                Divider()

                // Input area
                inputArea
            }
        }
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: session.purpose.icon)
                .foregroundStyle(purposeColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(session.ticketSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Toggle diff preview if there's an active change set
            if activeChangeSet != nil {
                Button {
                    showingDiffPreview.toggle()
                } label: {
                    Image(systemName: showingDiffPreview ? "bubble.left.and.bubble.right" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(showingDiffPreview ? "Show chat" : "Show changes")
                .accessibilityLabel(showingDiffPreview ? "Show chat" : "Show changes")
            }

            if session.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Generating response")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Message List or Empty State

    @ViewBuilder
    private var messageListOrEmptyState: some View {
        let visibleMessages = session.messages.filter { $0.role != .system }

        if visibleMessages.isEmpty && !session.isGenerating && session.errorMessage == nil && session.changeSets.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleMessages) { message in
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .contextMenu {
                                        if !message.content.isEmpty {
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(message.content, forType: .string)
                                            } label: {
                                                Label("Copy Message", systemImage: "doc.on.doc")
                                            }
                                        }
                                    }

                                // Show "Extract Changes" button on completed assistant messages
                                // that contain code blocks
                                if message.role == .assistant
                                    && !message.isStreaming
                                    && !message.content.isEmpty
                                    && containsCodeBlocks(message.content) {
                                    extractChangesButton(for: message)
                                }
                            }
                        }

                        // Error message
                        if let error = session.errorMessage {
                            errorView(error)
                        }

                        // Show existing change sets for this session
                        if !session.changeSets.isEmpty {
                            changeSetsSection
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: session.messages.last?.content) { _, _ in
                    if isAtBottom {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: session.purpose.icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(emptyStateSubtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty chat. \(emptyStateSubtitle)")
    }

    private var emptyStateTitle: String {
        switch session.purpose {
        case .plan: "Ready to Plan"
        case .implement: "Ready to Implement"
        case .review: "Ready to Review"
        case .general: "Start a Conversation"
        }
    }

    private var emptyStateSubtitle: String {
        switch session.purpose {
        case .plan: "Send a message to start planning the implementation for \(session.ticketKey)."
        case .implement: "Send a message to start generating code changes for \(session.ticketKey)."
        case .review: "Send a message to start reviewing the implementation for \(session.ticketKey)."
        case .general: "Type a message below to start chatting about \(session.ticketKey)."
        }
    }

    // MARK: - Extract Changes Button

    private func extractChangesButton(for message: ChatMessage) -> some View {
        Button {
            extractChanges(from: message)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                Text("Extract Changes")
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.orange)
        .accessibilityLabel("Extract code changes from this message")
    }

    // MARK: - Change Sets Section

    private var changeSetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Extracted Changes")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            ForEach(session.changeSets) { changeSet in
                changeSetRow(changeSet)
            }
        }
    }

    private func changeSetRow(_ changeSet: ChangeSet) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(changeSet.description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(changeSet.changes.count) files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if changeSet.isCommitted {
                        Label("Committed", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if changeSet.appliedCount > 0 {
                        Text("\(changeSet.appliedCount)/\(changeSet.changes.count) applied")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            Button {
                activeChangeSet = changeSet
                showingDiffPreview = true
            } label: {
                Text("Review")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel("Review change set: \(changeSet.description)")
        }
        .padding(8)
        .background(.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Type a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        sendMessage()
                    }
                }
                .accessibilityLabel("Message input")
                .accessibilityHint("Type a message and press Return to send")

            if session.isGenerating {
                // Stop generating button
                Button {
                    appState.chatManager.stopGenerating(session: session)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop generating")
                .accessibilityLabel("Stop generating response")
            } else {
                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? purposeColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel("Send message")
                .accessibilityHint(canSend ? "Send the current message" : "Type a message first")
            }
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Retry") {
                Task {
                    await appState.chatManager.retry(session: session)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Retry sending message")
        }
        .padding(12)
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !session.isGenerating
    }

    private var purposeColor: Color {
        switch session.purpose {
        case .plan: .blue
        case .implement: .orange
        case .review: .green
        case .general: .purple
        }
    }

    /// Check if a markdown string contains fenced code blocks.
    private func containsCodeBlocks(_ content: String) -> Bool {
        let pattern = "```"
        var count = 0
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: pattern, range: searchRange) {
            count += 1
            if count >= 2 { return true } // Need at least open + close
            searchRange = range.upperBound..<content.endIndex
        }
        return false
    }

    /// Extract file changes from a message and create a ChangeSet.
    private func extractChanges(from message: ChatMessage) {
        let fileChanges = CodeBlockParser.extractFileChanges(from: message.content)
        guard !fileChanges.isEmpty else { return }

        let changeSet = ChangeSet(
            ticketKey: session.ticketKey,
            description: "Changes from \(session.purpose.displayName) chat",
            changes: fileChanges,
            commitMessage: GitClient.commitMessage(
                ticketKey: session.ticketKey,
                description: "Implement \(session.ticketSummary)"
            ),
            branchName: GitClient.branchName(
                ticketKey: session.ticketKey,
                summary: session.ticketSummary
            )
        )

        session.changeSets.append(changeSet)
        activeChangeSet = changeSet
        showingDiffPreview = true

        // Notify persistence
        appState.chatManager.sessionDidUpdateChangeSets(session)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isGenerating else { return }
        inputText = ""
        Task {
            await appState.chatManager.sendMessage(text, in: session)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = session.messages.last(where: { $0.role != .system }) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Message Bubble

@MainActor
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    Image(systemName: message.role == .user ? "person.fill" : "sparkle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(message.role == .user ? "You" : "Copilot")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                // Content
                if message.content.isEmpty && message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(12)
                    .accessibilityLabel("Copilot is thinking")
                } else {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(
                            message.role == .user
                                ? Color.accentColor.opacity(0.15)
                                : Color.secondary.opacity(0.08)
                        )
                        .cornerRadius(12)
                }

                // Streaming indicator
                if message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Streaming...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Response is streaming")
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Copilot"): \(message.content.isEmpty && message.isStreaming ? "Thinking" : message.content)")
    }
}
