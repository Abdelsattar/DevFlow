import SwiftUI
import SwiftData
import Foundation

// MARK: - Auth Method Enums

enum JiraAuthMethod: String, Codable {
    case basicAuth
    case oauth
}

enum CopilotAuthMethod: String, Codable {
    case oauthDeviceFlow
    case externalGateway
}

@MainActor
@Observable
final class AppState {
    /// Shared singleton — ensures the Settings scene and main window
    /// always reference the same instance, working around the SwiftUI
    /// @Observable + Settings scene environment propagation bug on macOS.
    static let shared = AppState()

    private enum DefaultsKeys {
        static let lastActiveTicketKey = "lastActiveTicketKey"
        static let ticketScope = "ticketScope"
        static let assigneeFilter = "assigneeFilter"
        static let filterComponentId = "filterComponentId"
        static let filterStatus = "filterStatus"
    }

    // MARK: - Onboarding

    /// Backed by a stored property so @Observable can track changes and trigger SwiftUI re-renders.
    /// UserDefaults is kept in sync via didSet.
    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "isOnboardingComplete") {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: "isOnboardingComplete") }
    }

    // MARK: - Settings (persisted in UserDefaults)

    var jiraBaseURL: String {
        get { UserDefaults.standard.string(forKey: "jiraBaseURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "jiraBaseURL") }
    }

    var jiraEmail: String {
        get { UserDefaults.standard.string(forKey: "jiraEmail") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "jiraEmail") }
    }

    var jiraProjectKeys: [String] {
        get { UserDefaults.standard.stringArray(forKey: "jiraProjectKeys") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "jiraProjectKeys") }
    }

    var selectedComponentIds: [String] {
        get { UserDefaults.standard.stringArray(forKey: "selectedComponentIds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "selectedComponentIds") }
    }

    var githubHost: String {
        get { UserDefaults.standard.string(forKey: "githubHost") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "githubHost") }
    }

    var githubOrganization: String {
        get { UserDefaults.standard.string(forKey: "githubOrganization") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "githubOrganization") }
    }

    // MARK: - Jira OAuth Settings

    var jiraAuthMethod: JiraAuthMethod {
        get {
            let raw = UserDefaults.standard.string(forKey: "jiraAuthMethod") ?? "basicAuth"
            return JiraAuthMethod(rawValue: raw) ?? .basicAuth
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "jiraAuthMethod") }
    }

    var jiraOAuthClientId: String {
        get { UserDefaults.standard.string(forKey: "jiraOAuthClientId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "jiraOAuthClientId") }
    }

    var jiraCloudId: String {
        get { UserDefaults.standard.string(forKey: "jiraCloudId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "jiraCloudId") }
    }

    var jiraCloudName: String {
        get { UserDefaults.standard.string(forKey: "jiraCloudName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "jiraCloudName") }
    }

    // MARK: - Copilot Settings (kept for backward compat, but default changes)

    var copilotGatewayURL: String {
        get { UserDefaults.standard.string(forKey: "copilotGatewayURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "copilotGatewayURL") }
    }

    var copilotAuthMethod: CopilotAuthMethod {
        get {
            let raw = UserDefaults.standard.string(forKey: "copilotAuthMethod") ?? "oauthDeviceFlow"
            return CopilotAuthMethod(rawValue: raw) ?? .oauthDeviceFlow
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "copilotAuthMethod") }
    }

    var workspacePath: String {
        get { UserDefaults.standard.string(forKey: "workspacePath") ?? NSHomeDirectory() + "/Projects" }
        set { UserDefaults.standard.set(newValue, forKey: "workspacePath") }
    }

    // MARK: - Runtime State

    var tickets: [JiraTicket] = []
    var availableComponents: [JiraComponent] = []
    var selectedTicket: JiraTicket? {
        didSet {
            if let key = selectedTicket?.key {
                UserDefaults.standard.set(key, forKey: DefaultsKeys.lastActiveTicketKey)
            }
        }
    }
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Filter State (persisted via UserDefaults)

    var ticketScope: TicketScope = {
        let rawValue = UserDefaults.standard.string(forKey: DefaultsKeys.ticketScope) ?? TicketScope.currentSprint.rawValue
        return TicketScope(rawValue: rawValue) ?? .currentSprint
    }() {
        didSet { UserDefaults.standard.set(ticketScope.rawValue, forKey: DefaultsKeys.ticketScope) }
    }

    var assigneeFilter: AssigneeFilter = {
        let rawValue = UserDefaults.standard.string(forKey: DefaultsKeys.assigneeFilter) ?? AssigneeFilter.all.rawValue
        return AssigneeFilter(rawValue: rawValue) ?? .all
    }() {
        didSet { UserDefaults.standard.set(assigneeFilter.rawValue, forKey: DefaultsKeys.assigneeFilter) }
    }

    var searchText: String = ""

    var filterComponentId: String? = UserDefaults.standard.string(forKey: DefaultsKeys.filterComponentId) {
        didSet { UserDefaults.standard.set(filterComponentId, forKey: DefaultsKeys.filterComponentId) }
    }

    var filterStatus: String? = UserDefaults.standard.string(forKey: DefaultsKeys.filterStatus) {
        didSet { UserDefaults.standard.set(filterStatus, forKey: DefaultsKeys.filterStatus) }
    }

    // MARK: - Services

    let keychainService = KeychainService()

    @ObservationIgnored
    private(set) lazy var jiraService: JiraService = JiraService(appState: self)

    @ObservationIgnored
    private(set) lazy var githubService: GitHubService = GitHubService(appState: self)

    @ObservationIgnored
    private(set) lazy var copilotService: CopilotService = CopilotService(appState: self)

    @ObservationIgnored
    private(set) lazy var copilotAuthService: CopilotAuthService = CopilotAuthService(appState: self)

    @ObservationIgnored
    private(set) lazy var jiraOAuthService: JiraOAuthService = JiraOAuthService(appState: self)

    @ObservationIgnored
    private(set) lazy var chatManager: ChatManager = ChatManager(appState: self)

    @ObservationIgnored
    private(set) lazy var gitClient: GitClient = GitClient(appState: self)

    @ObservationIgnored
    private(set) lazy var autonomousFlowOrchestrator: AutonomousFlowOrchestrator = AutonomousFlowOrchestrator(appState: self)

    // MARK: - Persistence

    /// SwiftData model container for chat session persistence.
    @ObservationIgnored
    private(set) var modelContainer: ModelContainer?

    /// Set up SwiftData and connect persistence to ChatManager.
    /// Call once on app startup.
    func configurePersistence() {
        do {
            let schema = Schema([
                PersistentChatSession.self,
                PersistentChatMessage.self,
                PersistentChangeSet.self,
                PersistentFileChange.self,
                PersistentAutonomousFlowRun.self,
            ])
            let config = ModelConfiguration(
                "DevFlowChat",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            self.modelContainer = container
            chatManager.configurePersistence(modelContainer: container)
            chatManager.loadPersistedSessions()
            autonomousFlowOrchestrator.loadPersistedRuns()
        } catch {
            print("[AppState] Failed to configure SwiftData: \(error)")
            // App continues without persistence — sessions will be in-memory only
        }
    }

    // MARK: - Computed

    var filteredTickets: [JiraTicket] {
        var result = tickets

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.key.lowercased().contains(query) ||
                $0.fields.summary.lowercased().contains(query)
            }
        }

        if let componentId = filterComponentId {
            result = result.filter { ticket in
                ticket.fields.components.contains { $0.id == componentId }
            }
        }

        if let status = filterStatus {
            result = result.filter { $0.fields.status.name == status }
        }

        return result
    }

    var lastActiveTicketKey: String? {
        UserDefaults.standard.string(forKey: DefaultsKeys.lastActiveTicketKey)
    }

    // MARK: - Actions

    @discardableResult
    func navigateToTicket(_ ticket: JiraTicket) -> Bool {
        selectedTicket = ticket
        return true
    }

    @discardableResult
    func navigateToTicket(key: String) -> Bool {
        guard let ticket = tickets.first(where: { $0.key == key }) else {
            return false
        }
        selectedTicket = ticket
        return true
    }

    @discardableResult
    func resumeLastActiveTicket() -> Bool {
        guard let key = lastActiveTicketKey else { return false }
        return navigateToTicket(key: key)
    }

    /// Start a plan chat from quick actions using current selection, last active,
    /// or the first available ticket as a fallback.
    @discardableResult
    func startPlanChatFromQuickAction() -> Bool {
        if let selectedTicket {
            _ = chatManager.createSession(ticket: selectedTicket, purpose: .plan)
            return true
        }

        if resumeLastActiveTicket(), let selectedTicket {
            _ = chatManager.createSession(ticket: selectedTicket, purpose: .plan)
            return true
        }

        guard let fallbackTicket = tickets.first else {
            return false
        }

        selectedTicket = fallbackTicket
        _ = chatManager.createSession(ticket: fallbackTicket, purpose: .plan)
        return true
    }

    @MainActor
    func loadTickets() async {
        // OAuth uses cloud ID, Basic Auth uses base URL + email
        let hasOAuthConfig = jiraAuthMethod == .oauth && !jiraCloudId.isEmpty
        let hasBasicAuthConfig = jiraAuthMethod == .basicAuth && !jiraBaseURL.isEmpty && !jiraEmail.isEmpty
        guard hasOAuthConfig || hasBasicAuthConfig else { return }
        guard !jiraProjectKeys.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            var allTickets: [JiraTicket] = []
            for project in jiraProjectKeys {
                let projectTickets = try await jiraService.fetchTickets(
                    project: project,
                    scope: ticketScope,
                    assigneeFilter: assigneeFilter
                )
                allTickets.append(contentsOf: projectTickets)
            }
            tickets = allTickets.sorted { $0.key > $1.key }

            if let selectedKey = selectedTicket?.key {
                selectedTicket = tickets.first(where: { $0.key == selectedKey })
            } else if let lastActiveTicketKey {
                selectedTicket = tickets.first(where: { $0.key == lastActiveTicketKey })
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func loadComponents() async {
        let hasOAuthConfig = jiraAuthMethod == .oauth && !jiraCloudId.isEmpty
        let hasBasicAuthConfig = jiraAuthMethod == .basicAuth && !jiraBaseURL.isEmpty
        guard hasOAuthConfig || hasBasicAuthConfig else { return }
        guard !jiraProjectKeys.isEmpty else { return }

        do {
            var allComponents: [JiraComponent] = []
            for project in jiraProjectKeys {
                let components = try await jiraService.fetchComponents(project: project)
                allComponents.append(contentsOf: components)
            }
            availableComponents = allComponents
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
