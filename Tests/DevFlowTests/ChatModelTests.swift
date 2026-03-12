import Testing
@testable import DevFlow

// MARK: - Chat Model Tests

@Suite("Chat Model Tests")
struct ChatModelTests {

    // MARK: - Helpers

    /// Create a minimal JiraTicket for testing.
    private func makeSampleTicket(
        key: String = "PLAT-123",
        summary: String = "Add user authentication"
    ) -> JiraTicket {
        JiraTicket(
            id: "10001",
            key: key,
            fields: JiraIssueFields(
                summary: summary,
                description: nil,
                status: JiraStatus(id: "1", name: "To Do", iconUrl: nil),
                priority: JiraPriority(id: "3", name: "Medium", iconUrl: nil),
                assignee: JiraUser(accountId: "abc", displayName: "Mohamed", active: true, avatarUrls: nil),
                components: [JiraComponent(id: "100", name: "auth-service", description: nil)],
                comment: nil,
                issuetype: JiraIssueType(id: "10001", name: "Story", iconUrl: nil)
            )
        )
    }

    // MARK: - ChatMessage Tests

    @Test("Create chat messages with convenience methods")
    func chatMessageConvenience() {
        let system = ChatMessage.system("You are a helpful assistant.")
        #expect(system.role == .system)
        #expect(system.content == "You are a helpful assistant.")
        #expect(!system.isStreaming)

        let user = ChatMessage.user("Hello!")
        #expect(user.role == .user)
        #expect(user.content == "Hello!")

        let assistant = ChatMessage.assistant("Hi there!", isStreaming: true)
        #expect(assistant.role == .assistant)
        #expect(assistant.isStreaming)
    }

    // MARK: - ChatSession Tests

    @Test("Chat session manages messages correctly")
    func chatSessionMessages() {
        let session = ChatSession(
            ticketKey: "PLAT-123",
            ticketSummary: "Test ticket",
            purpose: .plan,
            messages: [.system("System prompt")]
        )

        #expect(session.title == "Plan: PLAT-123")
        #expect(session.subtitle == "Test ticket")
        #expect(session.messages.count == 1)
        #expect(!session.isGenerating)

        // Add user message
        session.addUserMessage("Create a plan")
        #expect(session.messages.count == 2)
        #expect(session.messages[1].role == .user)

        // Begin assistant response
        session.beginAssistantMessage()
        #expect(session.messages.count == 3)
        #expect(session.isGenerating)
        #expect(session.messages[2].isStreaming)

        // Stream chunks
        session.appendToCurrentMessage("Here is ")
        session.appendToCurrentMessage("the plan.")
        #expect(session.messages[2].content == "Here is the plan.")

        // Finish
        session.finishCurrentMessage()
        #expect(!session.isGenerating)
        #expect(!session.messages[2].isStreaming)
    }

    @Test("Chat session handles errors correctly")
    func chatSessionError() {
        let session = ChatSession(
            ticketKey: "PLAT-456",
            ticketSummary: "Error test",
            purpose: .implement
        )

        session.beginAssistantMessage()
        #expect(session.isGenerating)

        session.setError("Network timeout")
        #expect(!session.isGenerating)
        #expect(session.errorMessage == "Network timeout")
        // Empty streaming message should be removed
        #expect(session.messages.isEmpty)
    }

    @Test("Chat session error preserves partial content")
    func chatSessionErrorPreservesContent() {
        let session = ChatSession(
            ticketKey: "PLAT-789",
            ticketSummary: "Partial content test",
            purpose: .review
        )

        session.beginAssistantMessage()
        session.appendToCurrentMessage("Partial response")
        session.setError("Connection reset")

        // Partial message should be kept
        #expect(session.messages.count == 1)
        #expect(session.messages[0].content == "Partial response")
        #expect(!session.messages[0].isStreaming)
    }

    @Test("Chat session apiMessages formats correctly")
    func chatSessionApiMessages() {
        let session = ChatSession(
            ticketKey: "PLAT-100",
            ticketSummary: "API format test",
            purpose: .general,
            messages: [
                .system("You are helpful."),
                .user("Hi"),
                .assistant("Hello!")
            ]
        )

        let api = session.apiMessages
        #expect(api.count == 3)
        #expect(api[0]["role"] == "system")
        #expect(api[0]["content"] == "You are helpful.")
        #expect(api[1]["role"] == "user")
        #expect(api[2]["role"] == "assistant")
    }

    @Test("Chat session lastMessagePreview skips system messages")
    func chatSessionPreview() {
        let session = ChatSession(
            ticketKey: "PLAT-200",
            ticketSummary: "Preview test",
            purpose: .plan,
            messages: [.system("System prompt")]
        )

        #expect(session.lastMessagePreview == nil)

        session.addUserMessage("What should I do?")
        #expect(session.lastMessagePreview == "What should I do?")
    }

    // MARK: - ChatPurpose Tests

    @Test("Chat purpose display properties")
    func chatPurposeProperties() {
        #expect(ChatPurpose.plan.displayName == "Plan")
        #expect(ChatPurpose.implement.displayName == "Implement")
        #expect(ChatPurpose.review.displayName == "Review")
        #expect(ChatPurpose.general.displayName == "Chat")

        // Icons should be non-empty SF Symbol names
        #expect(!ChatPurpose.plan.icon.isEmpty)
        #expect(!ChatPurpose.implement.icon.isEmpty)
        #expect(!ChatPurpose.review.icon.isEmpty)
        #expect(!ChatPurpose.general.icon.isEmpty)
    }

    // MARK: - PromptBuilder Tests

    @Test("PromptBuilder creates system prompt for plan purpose")
    func promptBuilderPlan() {
        let ticket = makeSampleTicket()
        let prompt = PromptBuilder.buildSystemPrompt(ticket: ticket, purpose: .plan)

        #expect(prompt.contains("PLAT-123"))
        #expect(prompt.contains("Add user authentication"))
        #expect(prompt.contains("plan"))
        #expect(prompt.contains("auth-service"))
        #expect(prompt.contains("Medium"))
        #expect(prompt.contains("Story"))
    }

    @Test("PromptBuilder creates system prompt for implement purpose")
    func promptBuilderImplement() {
        let ticket = makeSampleTicket()
        let prompt = PromptBuilder.buildSystemPrompt(ticket: ticket, purpose: .implement)

        #expect(prompt.contains("PLAT-123"))
        #expect(prompt.contains("production-quality code"))
    }

    @Test("PromptBuilder creates system prompt for review purpose")
    func promptBuilderReview() {
        let ticket = makeSampleTicket()
        let prompt = PromptBuilder.buildSystemPrompt(ticket: ticket, purpose: .review)

        #expect(prompt.contains("PLAT-123"))
        #expect(prompt.contains("acceptance criteria"))
    }

    @Test("PromptBuilder creates initial user messages for workflow purposes")
    func promptBuilderInitialMessages() {
        let planMsg = PromptBuilder.buildInitialUserMessage(purpose: .plan)
        #expect(planMsg != nil)
        #expect(planMsg?.contains("implementation plan") == true)

        let implMsg = PromptBuilder.buildInitialUserMessage(purpose: .implement)
        #expect(implMsg != nil)

        let reviewMsg = PromptBuilder.buildInitialUserMessage(purpose: .review)
        #expect(reviewMsg != nil)

        let generalMsg = PromptBuilder.buildInitialUserMessage(purpose: .general)
        #expect(generalMsg == nil) // General chats don't auto-send
    }

    @Test("PromptBuilder includes ticket description in context")
    func promptBuilderWithDescription() {
        let adfDoc = ADFDocument(
            type: "doc",
            version: 1,
            content: [
                ADFNode(type: "paragraph", text: nil, content: [
                    ADFNode(type: "text", text: "Implement OAuth2 login flow", content: nil, marks: nil, attrs: nil)
                ], marks: nil, attrs: nil)
            ]
        )

        let ticket = JiraTicket(
            id: "10002",
            key: "PLAT-456",
            fields: JiraIssueFields(
                summary: "OAuth login",
                description: adfDoc,
                status: JiraStatus(id: "1", name: "In Progress", iconUrl: nil),
                priority: nil,
                assignee: nil,
                components: [],
                comment: nil,
                issuetype: nil
            )
        )

        let prompt = PromptBuilder.buildSystemPrompt(ticket: ticket, purpose: .plan)
        #expect(prompt.contains("OAuth2 login flow"))
        #expect(prompt.contains("### Description"))
    }
}
