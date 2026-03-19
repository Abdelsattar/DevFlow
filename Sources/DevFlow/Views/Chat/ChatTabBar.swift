import SwiftUI

/// Horizontal tab bar showing all active chat sessions.
/// The user can switch between chats or close them.
@MainActor
struct ChatTabBar: View {
    @Environment(AppState.self) private var appState
    @State private var sessionToClose: ChatSession?

    var body: some View {
        let manager = appState.chatManager

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(manager.sessions) { session in
                    chatTab(session: session, isActive: session.id == manager.activeSessionId)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat sessions")
        .alert("Close Chat?", isPresented: closeAlertBinding) {
            Button("Cancel", role: .cancel) {
                sessionToClose = nil
            }
            Button("Close", role: .destructive) {
                if let session = sessionToClose {
                    appState.chatManager.closeSession(session)
                    sessionToClose = nil
                }
            }
        } message: {
            if let session = sessionToClose {
                Text("Close the \(session.purpose.displayName) chat for \(session.ticketKey)? This will permanently remove the chat history.")
            }
        }
    }

    private var closeAlertBinding: Binding<Bool> {
        Binding(
            get: { sessionToClose != nil },
            set: { if !$0 { sessionToClose = nil } }
        )
    }

    private func chatTab(session: ChatSession, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: session.purpose.icon)
                .font(.caption2)
                .foregroundStyle(purposeColor(session.purpose))

            Text(session.title)
                .font(.caption)
                .lineLimit(1)

            if session.isGenerating {
                ProgressView()
                    .controlSize(.mini)
            }

            // Close button
            Button {
                // If session has messages beyond system prompt, confirm
                let hasContent = session.messages.count > 1
                if hasContent {
                    sessionToClose = session
                } else {
                    appState.chatManager.closeSession(session)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.5)
            .accessibilityLabel("Close \(session.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.chatManager.switchTo(session: session)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title)\(isActive ? ", active" : "")\(session.isGenerating ? ", generating" : "")")
        .accessibilityHint("Tap to switch to this chat")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func purposeColor(_ purpose: ChatPurpose) -> Color {
        switch purpose {
        case .plan: .blue
        case .implement: .orange
        case .review: .green
        case .general: .purple
        }
    }
}
