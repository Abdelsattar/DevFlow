import Foundation

/// Builds prompts for the Copilot LLM from JIRA ticket context.
enum PromptBuilder {

    // MARK: - System Prompts

    /// Build the system prompt for a chat session based on ticket and purpose.
    static func buildSystemPrompt(ticket: JiraTicket, purpose: ChatPurpose) -> String {
        let ticketContext = buildTicketContext(ticket: ticket)

        switch purpose {
        case .plan:
            return """
            You are a senior software engineer helping plan the implementation of a JIRA ticket.

            \(ticketContext)

            Your role:
            - Analyze the ticket requirements thoroughly
            - Break down the work into clear, actionable implementation steps
            - Identify potential risks, edge cases, and dependencies
            - Suggest the files/components that need to be created or modified
            - Estimate relative complexity of each step
            - Consider testing strategy
            - Follow existing code patterns and conventions in the codebase

            Be specific and actionable. Reference file paths where relevant. \
            Think step-by-step and produce a plan that another engineer could follow.
            """

        case .implement:
            return """
            You are a senior software engineer implementing a JIRA ticket.

            \(ticketContext)

            Your role:
            - Write production-quality code that implements the requirements
            - Follow the existing codebase patterns and conventions
            - Include appropriate error handling
            - Write clean, readable code with meaningful names
            - Add comments only where the code isn't self-explanatory
            - Consider edge cases mentioned in the ticket

            IMPORTANT — Output format for code changes:
            For each file you create or modify, output the COMPLETE file content using this format:

            **`path/to/file.swift`** (new file)
            ```swift
            // full file content here
            ```

            Or for modifications:

            **`path/to/existing/file.swift`** (modify)
            ```swift
            // full updated file content here
            ```

            Always show the complete file content, not partial snippets. \
            Use relative paths from the project root. \
            Clearly mark each file as "(new file)" or "(modify)".
            """

        case .review:
            return """
            You are a senior software engineer reviewing code changes for a JIRA ticket.

            \(ticketContext)

            Your role:
            - Review the implementation against the acceptance criteria
            - Check for bugs, edge cases, and potential issues
            - Verify error handling is appropriate
            - Check code style and conventions consistency
            - Suggest improvements if any
            - Confirm whether the implementation fully addresses the ticket requirements

            Be constructive and specific. Reference line numbers and file paths where relevant.

            If the user provides a git diff, analyze each changed file systematically.
            """

        case .general:
            return """
            You are a helpful software engineering assistant. You are helping with work \
            related to a JIRA ticket.

            \(ticketContext)

            Answer questions, explain code, suggest approaches, and help with any \
            software engineering tasks related to this ticket.
            """
        }
    }

    // MARK: - Initial User Messages

    /// Build the initial user message that kicks off the conversation.
    /// Returns nil if no auto-message is needed (e.g. general chat).
    static func buildInitialUserMessage(purpose: ChatPurpose) -> String? {
        switch purpose {
        case .plan:
            return """
            Please analyze this ticket and create a detailed implementation plan. Include:

            1. **Summary** of what needs to be done
            2. **Implementation steps** broken down into small, actionable tasks
            3. **Files to create/modify** with brief descriptions of changes
            4. **Dependencies and risks** to watch out for
            5. **Testing strategy** — what should be tested and how
            6. **Estimated complexity** (simple / moderate / complex) with reasoning
            """

        case .implement:
            return """
            Based on this ticket, please implement the solution. \
            For each file, show the complete file content in fenced code blocks \
            with the file path on the line above. Walk me through the changes.
            """

        case .review:
            return """
            Please review the current implementation against the ticket's acceptance criteria. \
            Identify any gaps, bugs, or improvements needed.
            """

        case .general:
            return nil
        }
    }

    /// Build a review message that includes the actual git diff for context.
    static func buildReviewMessageWithDiff(_ diff: String) -> String {
        """
        Here is the git diff of all changes made for this ticket. \
        Please review them against the acceptance criteria:

        ```diff
        \(diff)
        ```
        """
    }

    /// Build a review message that includes a diff and the ticket's acceptance criteria
    /// extracted from the description. This provides structured context for the AI
    /// to verify the implementation against requirements.
    static func buildReviewWithACs(diff: String, ticket: JiraTicket) -> String {
        let description = ticket.fields.plainTextDescription

        var parts: [String] = []
        parts.append("Please review the following changes against the ticket's acceptance criteria.")
        parts.append("")

        if description != "No description" && !description.isEmpty {
            parts.append("### Ticket Description & Acceptance Criteria")
            parts.append(description)
            parts.append("")
        }

        parts.append("### Git Diff")
        parts.append("```diff")
        parts.append(diff)
        parts.append("```")
        parts.append("")
        parts.append("For each acceptance criterion, confirm whether it is met by the changes. ")
        parts.append("Flag any gaps, bugs, or improvements needed.")

        return parts.joined(separator: "\n")
    }

    /// Build a concise summary of changes suitable for a PR description.
    /// This is sent to the AI to generate a human-readable change summary.
    static func buildPRSummaryPrompt(ticket: JiraTicket, diff: String) -> String {
        """
        Based on the following JIRA ticket and git diff, write a concise PR description \
        (2-5 bullet points) summarizing what was changed and why. \
        Do NOT include the diff itself. Just summarize the changes in plain English.

        ## Ticket: \(ticket.key)
        **Summary:** \(ticket.fields.summary)

        ## Diff
        ```diff
        \(diff)
        ```
        """
    }

    // MARK: - Ticket Context

    /// Build a structured text block describing the ticket.
    private static func buildTicketContext(ticket: JiraTicket) -> String {
        var parts: [String] = []

        parts.append("## JIRA Ticket: \(ticket.key)")
        parts.append("**Summary:** \(ticket.fields.summary)")
        parts.append("**Status:** \(ticket.fields.status.name)")

        if let priority = ticket.fields.priority {
            parts.append("**Priority:** \(priority.name)")
        }

        if let issueType = ticket.fields.issuetype {
            parts.append("**Type:** \(issueType.name)")
        }

        if !ticket.fields.components.isEmpty {
            let names = ticket.fields.components.map(\.name).joined(separator: ", ")
            parts.append("**Components:** \(names)")
        }

        let description = ticket.fields.plainTextDescription
        if description != "No description" && !description.isEmpty {
            parts.append("")
            parts.append("### Description")
            parts.append(description)
        }

        if let comments = ticket.fields.comment?.comments, !comments.isEmpty {
            parts.append("")
            parts.append("### Comments")
            for comment in comments.suffix(5) { // Last 5 comments for context
                let author = comment.author?.displayName ?? "Unknown"
                let body = comment.plainTextBody.isEmpty ? "(no content)" : comment.plainTextBody
                parts.append("**\(author):** \(body)")
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Autonomous Flow Context Injection

    /// Build an implement user message that includes the plan from a prior session.
    static func buildImplementWithPlanContext(plan: String) -> String {
        """
        Here is the implementation plan from the planning phase. \
        Please implement the solution following this plan closely.

        ### Plan
        \(plan)

        For each file, show the complete file content in fenced code blocks \
        with the file path on the line above. Walk me through the changes.
        """
    }

    /// Build a rework user message that includes review feedback.
    static func buildReworkWithReviewFeedback(feedback: String) -> String {
        """
        The review found issues that need to be addressed. \
        Please implement the required changes based on this feedback.

        ### Review Feedback
        \(feedback)

        For each file, show the complete file content in fenced code blocks \
        with the file path on the line above.
        """
    }

    /// Build a review message with a verdict suffix for structured parsing.
    static func buildReviewWithVerdictSuffix(diff: String, ticket: JiraTicket) -> String {
        let baseReview = buildReviewWithACs(diff: diff, ticket: ticket)

        return baseReview + """

        
        IMPORTANT: After your review, you MUST end your response with exactly one of these lines:
        VERDICT: APPROVED
        or
        VERDICT: NEEDS_REWORK

        Use APPROVED if the implementation meets the acceptance criteria with no blocking issues.
        Use NEEDS_REWORK only if there are significant bugs, missing requirements, or critical issues.
        Minor style suggestions alone should still result in APPROVED.
        """
    }

    // MARK: - Review Verdict Parsing

    /// Parse a review verdict from AI response text.
    /// Looks for structured VERDICT: line first, then falls back to keyword matching.
    /// Defaults to approved if ambiguous.
    static func parseReviewVerdict(from text: String) -> ReviewVerdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for structured verdict (search from end of text)
        let lines = trimmed.components(separatedBy: "\n").reversed()
        for line in lines.prefix(10) {
            let upper = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if upper.contains("VERDICT:") {
                if upper.contains("NEEDS_REWORK") || upper.contains("NEEDS REWORK") {
                    return .needsRework
                }
                if upper.contains("APPROVED") {
                    return .approved
                }
            }
        }

        // Keyword fallback — look for strong rejection signals
        let lowerText = trimmed.lowercased()
        let reworkSignals = ["needs rework", "needs_rework", "must be fixed", "critical issue",
                             "blocking issue", "does not meet", "fails to meet", "missing requirement"]
        for signal in reworkSignals {
            if lowerText.contains(signal) {
                return .needsRework
            }
        }

        // Default to approved if ambiguous
        return .approved
    }
}
