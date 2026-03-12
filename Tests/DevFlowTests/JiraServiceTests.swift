import Testing
import Foundation
@testable import DevFlow

@Suite("JIRA Model Parsing Tests")
struct JiraModelTests {

    // MARK: - Search Response Parsing

    @Test("Parse JIRA search response with tickets")
    func parseSearchResponse() throws {
        let json = """
        {
            "isLast": false,
            "nextPageToken": "token-abc",
            "issues": [
                {
                    "id": "10001",
                    "key": "PLAT-123",
                    "fields": {
                        "summary": "Fix login bug on mobile",
                        "description": {
                            "type": "doc",
                            "version": 1,
                            "content": [
                                {
                                    "type": "paragraph",
                                    "content": [
                                        { "type": "text", "text": "The login flow is broken on iOS." }
                                    ]
                                }
                            ]
                        },
                        "status": {
                            "id": "10001",
                            "name": "In Progress"
                        },
                        "priority": {
                            "id": "2",
                            "name": "High"
                        },
                        "assignee": {
                            "accountId": "abc123",
                            "displayName": "Mohamed Mostafa",
                            "active": true
                        },
                        "components": [
                            {
                                "id": "10000",
                                "name": "Backend"
                            }
                        ],
                        "comment": {
                            "startAt": 0,
                            "maxResults": 5,
                            "total": 1,
                            "comments": [
                                {
                                    "id": "20001",
                                    "author": {
                                        "accountId": "def456",
                                        "displayName": "John Doe",
                                        "active": true
                                    },
                                    "body": {
                                        "type": "doc",
                                        "version": 1,
                                        "content": [
                                            {
                                                "type": "paragraph",
                                                "content": [
                                                    { "type": "text", "text": "Looking into this now." }
                                                ]
                                            }
                                        ]
                                    },
                                    "created": "2024-01-15T10:30:00.000+0000"
                                }
                            ]
                        },
                        "issuetype": {
                            "id": "10001",
                            "name": "Bug"
                        }
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(JiraSearchResponse.self, from: json)

        #expect(response.isLast == false)
        #expect(response.nextPageToken == "token-abc")
        #expect(response.issues.count == 1)

        let ticket = response.issues[0]
        #expect(ticket.key == "PLAT-123")
        #expect(ticket.fields.summary == "Fix login bug on mobile")
        #expect(ticket.fields.status.name == "In Progress")
        #expect(ticket.fields.priority?.name == "High")
        #expect(ticket.fields.assignee?.displayName == "Mohamed Mostafa")
        #expect(ticket.fields.components.count == 1)
        #expect(ticket.fields.components[0].name == "Backend")
        #expect(ticket.fields.issuetype?.name == "Bug")

        // Comments
        #expect(ticket.fields.comment?.comments.count == 1)
        #expect(ticket.fields.comment?.comments[0].author?.displayName == "John Doe")
    }

    // MARK: - ADF to Plain Text

    @Test("Convert ADF document to plain text")
    func adfToPlainText() throws {
        let json = """
        {
            "type": "doc",
            "version": 1,
            "content": [
                {
                    "type": "heading",
                    "attrs": { "level": 2 },
                    "content": [
                        { "type": "text", "text": "Steps to Reproduce" }
                    ]
                },
                {
                    "type": "orderedList",
                    "content": [
                        {
                            "type": "listItem",
                            "content": [
                                {
                                    "type": "paragraph",
                                    "content": [
                                        { "type": "text", "text": "Open the app" }
                                    ]
                                }
                            ]
                        },
                        {
                            "type": "listItem",
                            "content": [
                                {
                                    "type": "paragraph",
                                    "content": [
                                        { "type": "text", "text": "Tap on " },
                                        { "type": "text", "text": "Login", "marks": [{ "type": "strong" }] }
                                    ]
                                }
                            ]
                        }
                    ]
                },
                {
                    "type": "paragraph",
                    "content": [
                        { "type": "text", "text": "See error on screen." }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let doc = try decoder.decode(ADFDocument.self, from: json)

        let plainText = doc.toPlainText()
        #expect(plainText.contains("## Steps to Reproduce"))
        #expect(plainText.contains("1. Open the app"))
        #expect(plainText.contains("2. Tap on Login"))
        #expect(plainText.contains("See error on screen."))
    }

    // MARK: - Component Parsing

    @Test("Parse JIRA components array")
    func parseComponents() throws {
        let json = """
        [
            {
                "id": "10000",
                "name": "Backend",
                "description": "Backend services"
            },
            {
                "id": "10001",
                "name": "Frontend"
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let components = try decoder.decode([JiraComponent].self, from: json)

        #expect(components.count == 2)
        #expect(components[0].name == "Backend")
        #expect(components[0].description == "Backend services")
        #expect(components[1].name == "Frontend")
        #expect(components[1].description == nil)
    }

    // MARK: - Workflow State

    @Test("Workflow state transitions")
    func workflowStateTransitions() {
        let idle = WorkflowState.idle
        #expect(idle.canPlan == true)
        #expect(idle.canImplement == false)
        #expect(idle.canReview == false)
        #expect(idle.isInProgress == false)

        let planReady = WorkflowState.planReady
        #expect(planReady.canPlan == false)
        #expect(planReady.canImplement == true)
        #expect(planReady.canReview == false)

        let implReady = WorkflowState.implReady
        #expect(implReady.canImplement == false)
        #expect(implReady.canReview == true)

        let planning = WorkflowState.planning
        #expect(planning.isInProgress == true)

        let failed = WorkflowState.failed
        #expect(failed.canPlan == true)
    }

    // MARK: - Date Formatting

    @Test("Parse JIRA date strings")
    func parseDates() {
        let date1 = DateFormatting.parse("2024-01-15T10:30:00.000+0000")
        #expect(date1 != nil)

        let date2 = DateFormatting.parse("2024-01-15T10:30:00Z")
        #expect(date2 != nil)
    }
}
