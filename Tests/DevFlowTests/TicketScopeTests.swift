import Testing
@testable import DevFlow

@Suite("Ticket Scope Tests")
struct TicketScopeTests {

    @Test("Current sprint scope adds active sprint clause with assignee filter")
    func currentSprintJQL() {
        let jql = JiraService.makeTicketJQL(
            project: "IOS",
            scope: .currentSprint,
            assigneeFilter: .currentUser
        )

        #expect(jql.contains("project = IOS"))
        #expect(jql.contains("assignee = currentUser()"))
        #expect(jql.contains("status != Done"))
        #expect(jql.contains("sprint in openSprints()"))
        #expect(jql.hasSuffix("ORDER BY updated DESC"))
    }

    @Test("Current sprint scope without assignee filter omits assignee clause")
    func currentSprintAllUsersJQL() {
        let jql = JiraService.makeTicketJQL(
            project: "IOS",
            scope: .currentSprint,
            assigneeFilter: .all
        )

        #expect(jql.contains("project = IOS"))
        #expect(!jql.contains("assignee = currentUser()"))
        #expect(jql.contains("status != Done"))
        #expect(jql.contains("sprint in openSprints()"))
        #expect(jql.hasSuffix("ORDER BY updated DESC"))
    }

    @Test("All tickets scope omits sprint clause")
    func allTicketsJQL() {
        let jql = JiraService.makeTicketJQL(project: "IOS", scope: .allTickets)

        #expect(!jql.contains("openSprints()"))
        #expect(!jql.contains("sprint is EMPTY"))
    }

    @Test("Backlog scope adds empty sprint clause")
    func backlogJQL() {
        let jql = JiraService.makeTicketJQL(project: "IOS", scope: .backlog)

        #expect(jql.contains("sprint is EMPTY"))
        #expect(!jql.contains("openSprints()"))
    }
}
