import Foundation
import Testing
@testable import DevFlow

// MARK: - GitHub Service Helper Tests

@Suite("GitHubService parseRemoteURL Tests")
struct ParseRemoteURLTests {

    @Test("Parses SSH remote URL")
    func sshRemote() {
        let result = GitHubService.parseRemoteURL("git@github.example.com:test-org/example-repo.git")
        #expect(result != nil)
        #expect(result?.owner == "test-org")
        #expect(result?.name == "example-repo")
    }

    @Test("Parses HTTPS remote URL")
    func httpsRemote() {
        let result = GitHubService.parseRemoteURL("https://github.example.com/test-org/example-repo.git")
        #expect(result != nil)
        #expect(result?.owner == "test-org")
        #expect(result?.name == "example-repo")
    }

    @Test("Parses SSH URL without .git suffix")
    func sshWithoutGit() {
        let result = GitHubService.parseRemoteURL("git@github.example.com:org/repo")
        #expect(result != nil)
        #expect(result?.owner == "org")
        #expect(result?.name == "repo")
    }

    @Test("Parses HTTPS URL without .git suffix")
    func httpsWithoutGit() {
        let result = GitHubService.parseRemoteURL("https://github.example.com/org/repo")
        #expect(result != nil)
        #expect(result?.owner == "org")
        #expect(result?.name == "repo")
    }

    @Test("Returns nil for invalid URL")
    func invalidURL() {
        let result = GitHubService.parseRemoteURL("not-a-url")
        #expect(result == nil)
    }

    @Test("Handles nested org paths in HTTPS")
    func nestedPath() {
        let result = GitHubService.parseRemoteURL("https://github.com/deep/nested/repo.git")
        #expect(result != nil)
        #expect(result?.owner == "nested")
        #expect(result?.name == "repo")
    }
}

// MARK: - GitHub Service buildPRBody Tests

@Suite("GitHubService buildPRBody Tests")
struct BuildPRBodyTests {

    @Test("Generates PR body with JIRA link when base URL provided")
    func basicBody() {
        let body = GitHubService.buildPRBody(
            ticketKey: "PLAT-456",
            summary: "Add user authentication flow",
            jiraBaseURL: "https://example.atlassian.net"
        )
        #expect(body.contains("PLAT-456"))
        #expect(body.contains("https://example.atlassian.net/browse/PLAT-456"))
        #expect(body.contains("Add user authentication flow"))
    }

    @Test("Omits Jira section when base URL is empty")
    func bodyWithoutJiraURL() {
        let body = GitHubService.buildPRBody(
            ticketKey: "PLAT-456",
            summary: "Add user authentication flow"
        )
        #expect(body.contains("PLAT-456"))
        #expect(!body.contains("atlassian.net"))
        #expect(body.contains("Add user authentication flow"))
    }

    @Test("Includes change summary when provided")
    func bodyWithChanges() {
        let body = GitHubService.buildPRBody(
            ticketKey: "PLAT-789",
            summary: "Fix login bug",
            changeSummary: "- Modified: `src/auth/login.swift`\n- New File: `src/auth/token.swift`"
        )
        #expect(body.contains("## Changes"))
        #expect(body.contains("login.swift"))
        #expect(body.contains("token.swift"))
    }

    @Test("Omits Changes section when changeSummary is empty")
    func bodyWithoutChanges() {
        let body = GitHubService.buildPRBody(
            ticketKey: "PLAT-100",
            summary: "Update docs"
        )
        #expect(!body.contains("## Changes"))
    }
}

// MARK: - GitHub Model Decoding Tests

@Suite("GitHub Model Decoding Tests")
struct GitHubModelDecodingTests {

    @Test("Decodes GitHubUser from JSON")
    func decodeUser() throws {
        let json = """
        {
            "id": 42,
            "login": "testuser",
            "name": "Test User",
            "email": "testuser@example.com",
            "avatar_url": "https://example.com/avatar.png",
            "html_url": "https://github.example.com/testuser"
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(GitHubUser.self, from: json)
        #expect(user.id == 42)
        #expect(user.login == "testuser")
        #expect(user.name == "Test User")
        #expect(user.email == "testuser@example.com")
        #expect(user.avatarUrl == "https://example.com/avatar.png")
        #expect(user.htmlUrl == "https://github.example.com/testuser")
    }

    @Test("Decodes GitHubRepository from JSON")
    func decodeRepository() throws {
        let json = """
        {
            "id": 100,
            "name": "example-repo",
            "full_name": "test-org/example-repo",
            "owner": {
                "login": "test-org",
                "id": 42
            },
            "html_url": "https://github.example.com/test-org/example-repo",
            "clone_url": "https://github.example.com/test-org/example-repo.git",
            "ssh_url": "git@github.example.com:test-org/example-repo.git",
            "default_branch": "main",
            "private": true
        }
        """.data(using: .utf8)!

        let repo = try JSONDecoder().decode(GitHubRepository.self, from: json)
        #expect(repo.id == 100)
        #expect(repo.name == "example-repo")
        #expect(repo.fullName == "test-org/example-repo")
        #expect(repo.owner.login == "test-org")
        #expect(repo.defaultBranch == "main")
        #expect(repo.isPrivate == true)
        #expect(repo.sshUrl == "git@github.example.com:test-org/example-repo.git")
    }

    @Test("Decodes GitHubPullRequest from JSON")
    func decodePullRequest() throws {
        let json = """
        {
            "id": 200,
            "number": 15,
            "title": "PLAT-456: Add auth flow",
            "body": "## Summary\\nAdded auth",
            "state": "open",
            "html_url": "https://github.example.com/test-org/example-repo/pull/15",
            "head": { "ref": "feature/plat-456-auth", "sha": "abc123", "label": "test-org:feature/plat-456-auth" },
            "base": { "ref": "main", "sha": "def456", "label": "test-org:main" },
            "user": { "id": 42, "login": "testuser" },
            "created_at": "2025-03-01T10:00:00Z",
            "updated_at": "2025-03-01T12:00:00Z",
            "merged": false,
            "mergeable": true
        }
        """.data(using: .utf8)!

        let pr = try JSONDecoder().decode(GitHubPullRequest.self, from: json)
        #expect(pr.id == 200)
        #expect(pr.number == 15)
        #expect(pr.title == "PLAT-456: Add auth flow")
        #expect(pr.state == "open")
        #expect(pr.head.ref == "feature/plat-456-auth")
        #expect(pr.base.ref == "main")
        #expect(pr.merged == false)
        #expect(pr.mergeable == true)
        #expect(pr.user?.login == "testuser")
    }

    @Test("Decodes CreatePullRequestBody round-trip")
    func createPRBody() throws {
        let original = CreatePullRequestBody(
            title: "PLAT-123: Test",
            body: "## Summary\nTest PR",
            head: "feature/plat-123-test",
            base: "master"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CreatePullRequestBody.self, from: data)

        #expect(decoded.title == original.title)
        #expect(decoded.body == original.body)
        #expect(decoded.head == original.head)
        #expect(decoded.base == original.base)
    }
}

// MARK: - JIRA Transition Model Decoding Tests

@Suite("JIRA Transition Model Tests")
struct JiraTransitionModelTests {

    @Test("Decodes JiraTransitionContainer from JSON")
    func decodeTransitions() throws {
        let json = """
        {
            "transitions": [
                {
                    "id": "11",
                    "name": "To Do",
                    "to": { "id": "10000", "name": "To Do" }
                },
                {
                    "id": "21",
                    "name": "In Progress",
                    "to": { "id": "10001", "name": "In Progress" }
                },
                {
                    "id": "31",
                    "name": "In Review",
                    "to": { "id": "10002", "name": "In Review" }
                },
                {
                    "id": "41",
                    "name": "Done",
                    "to": { "id": "10003", "name": "Done" }
                }
            ]
        }
        """.data(using: .utf8)!

        let container = try JSONDecoder().decode(JiraTransitionContainer.self, from: json)
        #expect(container.transitions.count == 4)
        #expect(container.transitions[0].id == "11")
        #expect(container.transitions[0].name == "To Do")
        #expect(container.transitions[0].to.name == "To Do")
        #expect(container.transitions[2].name == "In Review")
        #expect(container.transitions[2].to.id == "10002")
    }

    @Test("JiraTransition conforms to Identifiable")
    func transitionIdentifiable() throws {
        let json = """
        {
            "transitions": [
                { "id": "99", "name": "Start", "to": { "id": "1", "name": "Started" } }
            ]
        }
        """.data(using: .utf8)!

        let container = try JSONDecoder().decode(JiraTransitionContainer.self, from: json)
        let transition = container.transitions[0]
        #expect(transition.id == "99")
    }
}

// MARK: - PromptBuilder Phase 4 Tests

@Suite("PromptBuilder Review & PR Tests")
struct PromptBuilderPhase4Tests {

    private func makeTicket(
        key: String = "PLAT-100",
        summary: String = "Add feature X",
        description: ADFDocument? = nil
    ) -> JiraTicket {
        JiraTicket(
            id: "1",
            key: key,
            fields: JiraIssueFields(
                summary: summary,
                description: description,
                status: JiraStatus(id: "1", name: "In Progress", iconUrl: nil),
                priority: nil,
                assignee: nil,
                components: [],
                comment: nil,
                issuetype: nil
            )
        )
    }

    @Test("buildReviewWithACs includes description and diff")
    func reviewWithACs() {
        let adf = ADFDocument(type: "doc", version: 1, content: [
            ADFNode(type: "paragraph", text: nil, content: [
                ADFNode(type: "text", text: "User should be able to login with email and password.", content: nil, marks: nil, attrs: nil)
            ], marks: nil, attrs: nil)
        ])
        let ticket = makeTicket(description: adf)
        let diff = "+ func login() { }"

        let result = PromptBuilder.buildReviewWithACs(diff: diff, ticket: ticket)
        #expect(result.contains("Acceptance Criteria"))
        #expect(result.contains("login with email and password"))
        #expect(result.contains("func login()"))
        #expect(result.contains("```diff"))
    }

    @Test("buildReviewWithACs handles missing description")
    func reviewWithoutDescription() {
        let ticket = makeTicket()
        let diff = "+ some change"

        let result = PromptBuilder.buildReviewWithACs(diff: diff, ticket: ticket)
        #expect(result.contains("```diff"))
        #expect(!result.contains("Acceptance Criteria"))
    }

    @Test("buildPRSummaryPrompt includes ticket info and diff")
    func prSummaryPrompt() {
        let ticket = makeTicket(key: "PLAT-200", summary: "Refactor auth module")
        let diff = "- old code\n+ new code"

        let result = PromptBuilder.buildPRSummaryPrompt(ticket: ticket, diff: diff)
        #expect(result.contains("PLAT-200"))
        #expect(result.contains("Refactor auth module"))
        #expect(result.contains("old code"))
        #expect(result.contains("new code"))
    }
}
