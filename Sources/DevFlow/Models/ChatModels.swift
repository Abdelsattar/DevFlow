import Foundation

// MARK: - Chat Role

/// Role in a chat conversation, matching OpenAI API roles.
enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

// MARK: - Chat Message

/// A single message in a chat conversation.
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    /// Whether this message is still being streamed from the LLM.
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    /// Convenience for creating a system message.
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    /// Convenience for creating a user message.
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    /// Convenience for creating an assistant message (optionally streaming).
    static func assistant(_ content: String, isStreaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, isStreaming: isStreaming)
    }
}

// MARK: - Chat Session Purpose

/// What kind of workflow this chat session is for.
enum ChatPurpose: String, Codable, Sendable {
    case plan
    case implement
    case review
    case general
    
    var displayName: String {
        switch self {
        case .plan: "Plan"
        case .implement: "Implement"
        case .review: "Review"
        case .general: "Chat"
        }
    }
    
    var icon: String {
        switch self {
        case .plan: "doc.text.magnifyingglass"
        case .implement: "hammer"
        case .review: "checkmark.shield"
        case .general: "bubble.left.and.bubble.right"
        }
    }
    
    var accentColorName: String {
        switch self {
        case .plan: "blue"
        case .implement: "orange"
        case .review: "green"
        case .general: "purple"
        }
    }
}

// MARK: - Chat Session

/// A chat session tied to a JIRA ticket. Each ticket can have multiple sessions
/// (e.g. one for planning, one for implementation). Sessions persist their
/// message history and can be switched between in the UI.
@Observable
final class ChatSession: Identifiable {
    let id: UUID
    let ticketKey: String
    let ticketSummary: String
    let purpose: ChatPurpose
    let createdAt: Date
    var messages: [ChatMessage]
    var isGenerating: Bool
    var errorMessage: String?
    
    /// Change sets extracted from assistant messages in this session.
    var changeSets: [ChangeSet]
    
    /// Title shown in the chat list sidebar.
    var title: String {
        "\(purpose.displayName): \(ticketKey)"
    }
    
    /// Subtitle shown in the chat list sidebar.
    var subtitle: String {
        ticketSummary
    }
    
    /// The last message content, for preview in the chat list.
    var lastMessagePreview: String? {
        messages.last(where: { $0.role != .system })?.content
    }
    
    /// All messages formatted for the OpenAI API (role + content pairs).
    var apiMessages: [[String: String]] {
        messages.map { ["role": $0.role.rawValue, "content": $0.content] }
    }
    
    init(
        id: UUID = UUID(),
        ticketKey: String,
        ticketSummary: String,
        purpose: ChatPurpose,
        createdAt: Date = Date(),
        messages: [ChatMessage] = [],
        isGenerating: Bool = false,
        errorMessage: String? = nil,
        changeSets: [ChangeSet] = []
    ) {
        self.id = id
        self.ticketKey = ticketKey
        self.ticketSummary = ticketSummary
        self.purpose = purpose
        self.createdAt = createdAt
        self.messages = messages
        self.isGenerating = isGenerating
        self.errorMessage = errorMessage
        self.changeSets = changeSets
    }
    
    /// Append a user message and return it.
    @discardableResult
    func addUserMessage(_ content: String) -> ChatMessage {
        let message = ChatMessage.user(content)
        messages.append(message)
        return message
    }
    
    /// Start a new streaming assistant message and return it.
    @discardableResult
    func beginAssistantMessage() -> ChatMessage {
        let message = ChatMessage.assistant("", isStreaming: true)
        messages.append(message)
        isGenerating = true
        return message
    }
    
    /// Append a chunk of text to the current streaming assistant message.
    func appendToCurrentMessage(_ chunk: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].isStreaming else { return }
        messages[lastIndex].content += chunk
    }
    
    /// Mark the current streaming message as complete.
    func finishCurrentMessage() {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].isStreaming else { return }
        messages[lastIndex].isStreaming = false
        isGenerating = false
    }
    
    /// Mark the session as having an error.
    func setError(_ message: String) {
        isGenerating = false
        errorMessage = message
        // If there's an incomplete streaming message, mark it done
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].isStreaming {
            messages[lastIndex].isStreaming = false
            if messages[lastIndex].content.isEmpty {
                messages.removeLast()
            }
        }
    }
}
