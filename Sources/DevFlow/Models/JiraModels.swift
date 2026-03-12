import Foundation

// MARK: - Project

struct JiraProject: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let key: String
    let name: String

    static func == (lhs: JiraProject, rhs: JiraProject) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

// MARK: - Search Response

struct JiraSearchResponse: Codable, Sendable {
    let issues: [JiraTicket]
    let isLast: Bool?
    let nextPageToken: String?
}

enum TicketScope: String, CaseIterable, Codable, Sendable, Identifiable {
    case currentSprint
    case allTickets
    case backlog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentSprint:
            return "Current Sprint"
        case .allTickets:
            return "All Tickets"
        case .backlog:
            return "Backlog"
        }
    }

    var jqlClause: String? {
        switch self {
        case .currentSprint:
            return "sprint in openSprints()"
        case .allTickets:
            return nil
        case .backlog:
            return "sprint is EMPTY"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .currentSprint:
            return "No tickets in current sprint"
        case .allTickets:
            return "No tickets found"
        case .backlog:
            return "No backlog tickets"
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .currentSprint:
            return "Switch the scope to All Tickets or Backlog if you need a wider view."
        case .allTickets:
            return "Check your JIRA configuration or re-run the setup wizard."
        case .backlog:
            return "There are no assigned non-done tickets outside an active sprint right now."
        }
    }
}

// MARK: - Assignee Filter

/// Controls whether the ticket list shows all tickets or only those assigned to the current user.
enum AssigneeFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case all
    case currentUser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Everyone"
        case .currentUser:
            return "Assigned to Me"
        }
    }
}

// MARK: - Ticket (Issue)

struct JiraTicket: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let key: String
    let fields: JiraIssueFields

    static func == (lhs: JiraTicket, rhs: JiraTicket) -> Bool {
        lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

// MARK: - Issue Fields

struct JiraIssueFields: Codable, Sendable {
    let summary: String
    let description: ADFDocument?
    let status: JiraStatus
    let priority: JiraPriority?
    let assignee: JiraUser?
    let components: [JiraComponent]
    let comment: JiraCommentContainer?
    let issuetype: JiraIssueType?

    var plainTextDescription: String {
        description?.toPlainText() ?? "No description"
    }
}

// MARK: - Status

struct JiraStatus: Codable, Sendable {
    let id: String?
    let name: String
    let iconUrl: String?

    var color: StatusColor {
        switch name.lowercased() {
        case "to do", "open", "backlog":
            return .gray
        case "in progress", "in development":
            return .blue
        case "in review", "code review", "review":
            return .orange
        case "done", "closed", "resolved":
            return .green
        default:
            return .gray
        }
    }

    enum StatusColor: Sendable {
        case gray, blue, orange, green
    }
}

// MARK: - Priority

struct JiraPriority: Codable, Sendable {
    let id: String?
    let name: String
    let iconUrl: String?

    var icon: String {
        switch name.lowercased() {
        case "highest", "critical", "blocker":
            return "arrow.up.circle.fill"
        case "high":
            return "arrow.up.circle"
        case "medium":
            return "minus.circle"
        case "low":
            return "arrow.down.circle"
        case "lowest":
            return "arrow.down.circle.fill"
        default:
            return "minus.circle"
        }
    }
}

// MARK: - User

struct JiraUser: Codable, Sendable {
    let accountId: String?
    let displayName: String
    let active: Bool?
    let avatarUrls: JiraAvatarUrls?
}

struct JiraAvatarUrls: Codable, Sendable {
    let the16x16: String?
    let the24x24: String?
    let the32x32: String?
    let the48x48: String?

    enum CodingKeys: String, CodingKey {
        case the16x16 = "16x16"
        case the24x24 = "24x24"
        case the32x32 = "32x32"
        case the48x48 = "48x48"
    }
}

// MARK: - Component

struct JiraComponent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?

    static func == (lhs: JiraComponent, rhs: JiraComponent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Issue Type

struct JiraIssueType: Codable, Sendable {
    let id: String?
    let name: String
    let iconUrl: String?

    var icon: String {
        switch name.lowercased() {
        case "bug":
            return "ladybug"
        case "story", "user story":
            return "book"
        case "task":
            return "checkmark.square"
        case "epic":
            return "bolt"
        case "sub-task", "subtask":
            return "square.split.bottomrightquarter"
        default:
            return "doc"
        }
    }
}

// MARK: - Comments

struct JiraCommentContainer: Codable, Sendable {
    let startAt: Int?
    let maxResults: Int?
    let total: Int?
    let comments: [JiraComment]
}

struct JiraComment: Codable, Identifiable, Sendable {
    let id: String
    let author: JiraUser?
    let body: ADFDocument?
    let created: String?
    let updated: String?

    var plainTextBody: String {
        body?.toPlainText() ?? ""
    }
}

// MARK: - Transitions

struct JiraTransitionContainer: Codable, Sendable {
    let transitions: [JiraTransition]
}

struct JiraTransition: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let to: JiraTransitionTarget
}

struct JiraTransitionTarget: Codable, Sendable {
    let id: String
    let name: String
}
