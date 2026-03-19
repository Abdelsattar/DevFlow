import SwiftUI
import AppKit

@MainActor
struct SetupWizardView: View {
    @Environment(AppState.self) private var appState

    @State private var currentStep: Int = 0

    // Step 1: JIRA
    @State private var jiraAuthMethod: JiraAuthMethod = .oauth
    // Basic Auth fields
    @State private var jiraBaseURL: String = ""
    @State private var jiraEmail: String = ""
    @State private var jiraAPIToken: String = ""
    @State private var jiraConnectedEmail: String = ""
    @State private var isValidatingJiraToken: Bool = false
    @State private var jiraTokenPasted: Bool = false
    // OAuth fields
    @State private var jiraOAuthClientId: String = ""
    @State private var isJiraOAuthConnected: Bool = false
    @State private var jiraOAuthCloudName: String = ""
    @State private var isJiraAuthenticating: Bool = false
    @State private var jiraConnectionStatus: ConnectionStatus = .untested

    // Step 2: Projects
    @State private var availableProjects: [JiraProject] = []
    @State private var selectedProjectKey: String = ""
    @State private var isLoadingProjects: Bool = false
    @State private var projectLoadError: String?
    @State private var projectSearch: String = ""
    @State private var projectStartAt: Int = 0
    @State private var hasMoreProjects: Bool = false
    @State private var isFetchingMoreProjects: Bool = false
    @State private var projectSearchTask: Task<Void, Never>?

    // Step 3: GitHub
    @State private var githubHost: String = ""
    @State private var githubOrg: String = ""
    @State private var githubPAT: String = ""
    @State private var githubConnectionStatus: ConnectionStatus = .untested
    @State private var githubUser: GitHubUser?
    @State private var githubOrganizations: [GitHubOrganization] = []
    @State private var isValidatingGitHubToken: Bool = false
    @State private var githubTokenPasted: Bool = false
    @State private var githubOrgSearch: String = ""

    // Step 4: Copilot
    @State private var copilotAuthMethod: CopilotAuthMethod = .oauthDeviceFlow
    // Device Flow state
    @State private var isCopilotAuthenticated: Bool = false
    @State private var isCopilotAuthenticating: Bool = false
    @State private var deviceCode: DeviceCodeResponse?
    @State private var userCodeCopied: Bool = false
    @State private var copilotAuthTask: Task<Void, Never>?
    // External gateway state (legacy)
    @State private var copilotGatewayURL: String = ""
    @State private var copilotConnectionStatus: ConnectionStatus = .untested

    // Step 5: Workspace
    @State private var workspacePath: String = ""

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Header
            progressHeader

            Divider()

            // Step Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch currentStep {
                    case 0: jiraStep
                    case 1: projectStep
                    case 2: githubStep
                    case 3: copilotStep
                    case 4: workspaceStep
                    default: EmptyView()
                    }
                }
                .padding(24)
            }

            Divider()

            // Navigation
            navigationBar
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            // Pre-fill from existing settings when re-running the wizard
            jiraAuthMethod = appState.jiraAuthMethod
            jiraBaseURL = appState.jiraBaseURL.isEmpty ? "" : appState.jiraBaseURL
            jiraEmail = appState.jiraEmail
            jiraOAuthClientId = appState.jiraOAuthClientId
            selectedProjectKey = appState.jiraProjectKey
            githubHost = appState.githubHost.isEmpty ? "" : appState.githubHost
            githubOrg = appState.githubOrganization
            copilotAuthMethod = appState.copilotAuthMethod
            copilotGatewayURL = appState.copilotGatewayURL
            workspacePath = appState.workspacePath
        }
        .onDisappear {
            copilotAuthTask?.cancel()
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 12) {
            Text("Welcome to DevFlow")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)

            Text(stepTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Step 1 of 5: JIRA Configuration"
        case 1: return "Step 2 of 5: Select Projects & Components"
        case 2: return "Step 3 of 5: GitHub Enterprise"
        case 3: return "Step 4 of 5: Copilot AI"
        case 4: return "Step 5 of 5: Workspace Directory"
        default: return ""
        }
    }

    // MARK: - Step 1: JIRA

    private var jiraStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect to JIRA Cloud", systemImage: "ticket")
                .font(.headline)

            // Auth method picker
            Picker("Authentication", selection: $jiraAuthMethod) {
                Text("OAuth 2.0 (Recommended)").tag(JiraAuthMethod.oauth)
                Text("Basic Auth (API Token)").tag(JiraAuthMethod.basicAuth)
            }
            .pickerStyle(.segmented)
            .onChange(of: jiraAuthMethod) { _, _ in
                jiraConnectionStatus = .untested
            }

            if jiraAuthMethod == .oauth {
                jiraOAuthContent
            } else {
                jiraBasicAuthContent
            }
        }
    }

    // MARK: - Jira OAuth Content

    @ViewBuilder
    private var jiraOAuthContent: some View {
        if isJiraOAuthConnected {
            // Connected state
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Connected to \(jiraOAuthCloudName)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Authenticated via Atlassian OAuth 2.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") {
                    disconnectJiraOAuth()
                }
                .foregroundStyle(.red)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OAuth Client ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $jiraOAuthClientId, prompt: Text("Your Atlassian OAuth 2.0 Client ID"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    connectionStatusBadge(jiraConnectionStatus)
                    Spacer()
                    Button("Sign in with Atlassian") {
                        Task { await signInWithJiraOAuth() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jiraOAuthClientId.isEmpty || isJiraAuthenticating)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Setup:")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("1. Go to developer.atlassian.com/console/myapps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("2. Create an OAuth 2.0 (3LO) app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("3. Set callback URL to: devflow://oauth/callback/jira")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                        Text("4. Add scopes: read:jira-work, write:jira-work, read:jira-user, read:board-scope:jira-software, read:project:jira")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                Text("5. Copy the Client ID above")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Jira Basic Auth Content

    @ViewBuilder
    private var jiraBasicAuthContent: some View {
        if !jiraConnectedEmail.isEmpty {
            // Connected state
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected as \(jiraConnectedEmail)")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(jiraBaseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Disconnect") {
                    disconnectJiraBasicAuth()
                }
                .foregroundStyle(.red)
            }
            .padding(12)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
        } else {
            // Setup flow
            Text("Connect to your JIRA Cloud workspace using an API token.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Step 1: Base URL + Email
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Enter your JIRA details")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $jiraBaseURL, prompt: Text("https://yourcompany.atlassian.net"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $jiraEmail, prompt: Text("you@company.com"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
            }

            Divider()

            // Step 2: Generate + paste token
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Generate an API Token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Button {
                    if let url = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open Atlassian Account")
                    }
                }
                .buttonStyle(.borderedProminent)

                Text("This opens id.atlassian.com where you can generate an API token, then paste it below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Step 3: Paste token
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "3.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Paste your API token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                SecureField("", text: $jiraAPIToken, prompt: Text("Paste your API token here"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .onChange(of: jiraAPIToken) { _, newValue in
                        if newValue.count >= 10 && !jiraTokenPasted && !jiraEmail.isEmpty && !jiraBaseURL.isEmpty {
                            jiraTokenPasted = true
                            Task { await testJiraConnection() }
                        } else if newValue.isEmpty {
                            jiraTokenPasted = false
                            jiraConnectionStatus = .untested
                        }
                    }

                HStack {
                    connectionStatusBadge(jiraConnectionStatus)
                    Spacer()
                    if !jiraAPIToken.isEmpty {
                        Button("Verify Token") {
                            Task { await testJiraConnection() }
                        }
                        .disabled(isValidatingJiraToken || jiraBaseURL.isEmpty || jiraEmail.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Projects

    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Select Project", systemImage: "folder")
                .font(.headline)

            Text("Choose the JIRA project whose tickets you want to see in DevFlow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if availableProjects.isEmpty && isLoadingProjects {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading projects...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if availableProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = projectLoadError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Fetch Projects") {
                        Task { await fetchProjects() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Search bar — triggers a fresh server-side fetch after 300 ms
                TextField("", text: $projectSearch, prompt: Text("Search projects..."))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .onChange(of: projectSearch) { _, _ in
                        projectSearchTask?.cancel()
                        projectSearchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await fetchProjects()
                        }
                    }

                // Project list — single selection, selected project always pinned at top
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(availableProjects) { project in
                            Button {
                                // Set selection and move the chosen project to the top of the local list
                                selectedProjectKey = project.key
                                if let idx = availableProjects.firstIndex(where: { $0.key == project.key }), idx != 0 {
                                    var updated = availableProjects
                                    let pinned = updated.remove(at: idx)
                                    updated.insert(pinned, at: 0)
                                    availableProjects = updated
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedProjectKey == project.key ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedProjectKey == project.key ? Color.accentColor : .secondary)
                                        .frame(width: 16)
                                    projectAvatar(project)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(project.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text(project.key)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(selectedProjectKey == project.key ? Color.accentColor.opacity(0.08) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }

                        // Sentinel that triggers the next page when it scrolls into view
                        if hasMoreProjects {
                            Color.clear.frame(height: 1)
                                .onAppear {
                                    Task { await loadMoreProjects() }
                                }
                            if isFetchingMoreProjects {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Loading more…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: 260)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                if !selectedProjectKey.isEmpty {
                    Label("\(selectedProjectKey) selected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Refresh") {
                    Task { await fetchProjects() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .task {
            if availableProjects.isEmpty && !isLoadingProjects {
                await fetchProjects()
            }
        }
    }

    @ViewBuilder
    private func projectAvatar(_ project: JiraProject) -> some View {
        if let urlString = project.avatarUrls?.the48x48, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                default:
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 24, height: 24)
        } else {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    // MARK: - Step 3: GitHub

    private var githubStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("GitHub Enterprise", systemImage: "arrow.triangle.branch")
                .font(.headline)

            if let user = githubUser {
                // Connected state
                githubConnectedView(user: user)
            } else {
                // Setup flow
                githubSetupView
            }
        }
    }

    @ViewBuilder
    private func githubConnectedView(user: GitHubUser) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connected as \(user.name ?? user.login)")
                    .font(.body)
                    .fontWeight(.medium)
                Text("@\(user.login) on \(githubHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Disconnect") {
                disconnectGitHub()
            }
            .foregroundStyle(.red)
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)

        if !githubOrganizations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Organization")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let filtered = githubOrgSearch.isEmpty
                    ? githubOrganizations
                    : githubOrganizations.filter { $0.login.localizedCaseInsensitiveContains(githubOrgSearch) }
                let sorted = filtered.sorted { $0.login == githubOrg && $1.login != githubOrg }

                if githubOrganizations.count > 1 {
                    TextField("", text: $githubOrgSearch, prompt: Text("Search organizations..."))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sorted) { org in
                            Button {
                                githubOrg = org.login
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: githubOrg == org.login ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(githubOrg == org.login ? Color.accentColor : .secondary)
                                        .frame(width: 16)
                                    Image(systemName: "building.2")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(org.login)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        if let desc = org.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(githubOrg == org.login ? Color.accentColor.opacity(0.08) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: min(CGFloat(githubOrganizations.count) * 44, 200))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                if !githubOrg.isEmpty {
                    Label("\(githubOrg) selected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var githubSetupView: some View {
        Text("Connect to GitHub to create pull requests and manage repositories.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        // Host selection
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub Host")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("", text: $githubHost, prompt: Text("github.com or github.your-company.com"))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)

            Text("Leave blank for github.com. Change this only if you use a GitHub Enterprise instance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Step 1: Open GitHub to generate token
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "1.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Generate a Personal Access Token")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Button {
                let effectiveHost = githubHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty ? "github.com" : githubHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                if let url = URL(string: "https://\(effectiveHost)/settings/tokens/new?scopes=repo&description=DevFlow") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Generate Token on GitHub")
                }
            }
            .buttonStyle(.borderedProminent)

            let displayHost = githubHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty ? "github.com" : githubHost
            Text("Opens \(displayHost) in your browser. Select the 'repo' scope, then copy the generated token.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Step 2: Paste token
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "2.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Paste your token")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            SecureField("", text: $githubPAT, prompt: Text("Paste your Personal Access Token here"))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .onChange(of: githubPAT) { _, newValue in
                    // Auto-validate when a token is pasted (min length check to avoid partial input)
                    if newValue.count >= 10 && !githubTokenPasted {
                        githubTokenPasted = true
                        Task { await validateGitHubToken() }
                    } else if newValue.isEmpty {
                        githubTokenPasted = false
                        githubConnectionStatus = .untested
                    }
                }

            HStack {
                connectionStatusBadge(githubConnectionStatus)
                Spacer()
                if !githubPAT.isEmpty {
                    Button("Verify Token") {
                        Task { await validateGitHubToken() }
                    }
                    .disabled(isValidatingGitHubToken)
                }
            }
        }
    }

    private func validateGitHubToken() async {
        // Temporarily save host and token so the service can use them
        appState.githubHost = githubHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        try? appState.keychainService.saveOrUpdate(
            service: KeychainService.githubService,
            account: appState.githubHost,
            token: githubPAT
        )

        githubConnectionStatus = .testing
        isValidatingGitHubToken = true
        defer { isValidatingGitHubToken = false }

        do {
            let (user, orgs) = try await appState.githubService.validateTokenAndGetInfo()
            githubUser = user
            githubOrganizations = orgs
            githubConnectionStatus = .success

            // Auto-select org if there's only one
            if orgs.count == 1 {
                githubOrg = orgs[0].login
            }
        } catch {
            githubConnectionStatus = .failed(error.localizedDescription)
            githubTokenPasted = false
        }
    }

    private func disconnectGitHub() {
        githubUser = nil
        githubOrganizations = []
        githubPAT = ""
        githubOrg = ""
        githubConnectionStatus = .untested
        githubTokenPasted = false
        try? appState.keychainService.delete(
            service: KeychainService.githubService,
            account: appState.githubHost
        )
    }

    // MARK: - Step 4: Copilot

    private var copilotStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Copilot AI", systemImage: "brain")
                .font(.headline)

            // Auth method picker
            Picker("Method", selection: $copilotAuthMethod) {
                Text("GitHub Copilot (Recommended)").tag(CopilotAuthMethod.oauthDeviceFlow)
                Text("External Gateway").tag(CopilotAuthMethod.externalGateway)
            }
            .pickerStyle(.segmented)
            .onChange(of: copilotAuthMethod) { _, _ in
                copilotConnectionStatus = .untested
            }

            if copilotAuthMethod == .oauthDeviceFlow {
                copilotDeviceFlowContent
            } else {
                copilotGatewayContent
            }

            Text("You can skip this step and configure it later in Settings.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Copilot Device Flow Content

    @ViewBuilder
    private var copilotDeviceFlowContent: some View {
        if isCopilotAuthenticated {
            // Connected state
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Connected to GitHub Copilot", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Using your GitHub Copilot subscription directly. No external tools required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") {
                    disconnectCopilot()
                }
                .foregroundStyle(.red)
            }
        } else if let code = deviceCode, isCopilotAuthenticating {
            // Device code display
            copilotDeviceCodeView(code)
        } else {
            // Sign in prompt
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in with your GitHub account to use Copilot directly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("No external tools or npm packages required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .failed(let msg) = copilotConnectionStatus {
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    Button("Sign in with GitHub") {
                        startCopilotDeviceFlow()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCopilotAuthenticating)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Requirements:")
                    .font(.caption)
                    .fontWeight(.semibold)
                Label("Active GitHub Copilot subscription", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("GitHub.com account (not Enterprise)", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Copilot Device Code View

    @ViewBuilder
    private func copilotDeviceCodeView(_ code: DeviceCodeResponse) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("Enter this code on GitHub:")
                    .font(.subheadline)

                // Large, copyable user code
                HStack(spacing: 4) {
                    Text(code.userCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.userCode, forType: .string)
                        userCodeCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            userCodeCopied = false
                        }
                    } label: {
                        Image(systemName: userCodeCopied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(userCodeCopied ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy code to clipboard")
                }

                if userCodeCopied {
                    Text("Copied!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Divider()

            // Open GitHub link
            HStack {
                Text("Open:")
                    .font(.caption)
                if let url = URL(string: code.verificationUri) {
                    Link(code.verificationUri, destination: url)
                        .font(.caption)
                } else {
                    Text(code.verificationUri)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Polling indicator
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for authorization...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                cancelCopilotDeviceFlow()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Copilot Gateway Content (Legacy)

    @ViewBuilder
    private var copilotGatewayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gateway URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $copilotGatewayURL, prompt: Text("http://localhost:3030/v1"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
            }

            HStack {
                connectionStatusBadge(copilotConnectionStatus)
                Spacer()
                Button("Test Connection") {
                    Task { await testCopilotConnection() }
                }
                .disabled(copilotGatewayURL.isEmpty)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Setup:")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("1. npm install -g copilot-api")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("2. copilot-api start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Uses your existing GitHub Copilot subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 5: Workspace

    private var workspaceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Project Folder", systemImage: "folder.badge.gearshape")
                .font(.headline)

            Text("Where is your project repository located?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField("", text: $workspacePath)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)

                Button("Browse...") {
                    selectWorkspaceDirectory()
                }
            }

            Text("DevFlow will create branches and make changes inside this project folder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("You're all set!")
                    .font(.headline)
                Text("Click Finish to start using DevFlow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Skip") {
                    withAnimation { currentStep += 1 }
                }
                .foregroundStyle(.secondary)

                Button("Next") {
                    saveCurrentStep()
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            } else {
                Button("Finish") {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0:
            if jiraAuthMethod == .oauth {
                return isJiraOAuthConnected || !jiraOAuthClientId.isEmpty
            } else {
                return !jiraConnectedEmail.isEmpty || (!jiraBaseURL.isEmpty && !jiraEmail.isEmpty && !jiraAPIToken.isEmpty)
            }
        case 1: return !selectedProjectKey.isEmpty
        case 2: return true // GitHub is optional for initial setup
        case 3: return true // Copilot is optional
        case 4: return true
        default: return true
        }
    }

    // MARK: - Connection Status Badge

    @ViewBuilder
    private func connectionStatusBadge(_ status: ConnectionStatus) -> some View {
        switch status {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Testing...").font(.caption).foregroundStyle(.secondary)
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    // MARK: - Actions

    private func saveCurrentStep() {
        switch currentStep {
        case 0:
            appState.jiraAuthMethod = jiraAuthMethod

            if jiraAuthMethod == .oauth {
                appState.jiraOAuthClientId = jiraOAuthClientId.trimmingCharacters(in: .whitespaces)
                // OAuth tokens are already saved by the sign-in flow
            } else {
                appState.jiraBaseURL = jiraBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                appState.jiraEmail = jiraEmail.trimmingCharacters(in: .whitespaces)
                try? appState.keychainService.saveOrUpdate(
                    service: KeychainService.jiraService,
                    account: appState.jiraEmail,
                    token: jiraAPIToken
                )
            }
        case 1:
            appState.jiraProjectKey = selectedProjectKey
        case 2:
            appState.githubHost = githubHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            appState.githubOrganization = githubOrg.trimmingCharacters(in: .whitespaces)
            if !githubPAT.isEmpty {
                try? appState.keychainService.saveOrUpdate(
                    service: KeychainService.githubService,
                    account: appState.githubHost,
                    token: githubPAT
                )
            }
        case 3:
            appState.copilotAuthMethod = copilotAuthMethod
            if copilotAuthMethod == .externalGateway {
                appState.copilotGatewayURL = copilotGatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            }
            // Device flow tokens are already saved by the sign-in flow
        case 4:
            appState.workspacePath = workspacePath
        default:
            break
        }
    }

    private func finishSetup() {
        saveCurrentStep()
        appState.isOnboardingComplete = true

        Task {
            await appState.loadTickets()
        }
    }

    // MARK: - Jira OAuth Actions

    private func signInWithJiraOAuth() async {
        appState.jiraOAuthClientId = jiraOAuthClientId.trimmingCharacters(in: .whitespaces)
        jiraConnectionStatus = .testing
        isJiraAuthenticating = true
        defer { isJiraAuthenticating = false }

        do {
            try await appState.jiraOAuthService.authenticate()
            isJiraOAuthConnected = true
            jiraOAuthCloudName = appState.jiraCloudName
            jiraConnectionStatus = .success
        } catch {
            jiraConnectionStatus = .failed(error.localizedDescription)
        }
    }

    private func disconnectJiraOAuth() {
        appState.jiraOAuthService.signOut()
        isJiraOAuthConnected = false
        jiraOAuthCloudName = ""
        jiraConnectionStatus = .untested
    }

    // MARK: - Jira Basic Auth Actions

    private func testJiraConnection() async {
        // Temporarily save for testing
        appState.jiraAuthMethod = .basicAuth
        appState.jiraBaseURL = jiraBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        appState.jiraEmail = jiraEmail.trimmingCharacters(in: .whitespaces)
        try? appState.keychainService.saveOrUpdate(
            service: KeychainService.jiraService,
            account: appState.jiraEmail,
            token: jiraAPIToken
        )

        isValidatingJiraToken = true
        jiraConnectionStatus = .testing
        defer { isValidatingJiraToken = false }

        do {
            let ok = try await appState.jiraService.testConnection()
            if ok {
                jiraConnectedEmail = jiraEmail.trimmingCharacters(in: .whitespaces)
                jiraConnectionStatus = .success
            } else {
                jiraConnectionStatus = .failed("Connection failed")
                jiraTokenPasted = false
            }
        } catch {
            jiraConnectionStatus = .failed(error.localizedDescription)
            jiraTokenPasted = false
        }
    }

    // MARK: - Copilot Device Flow Actions

    private func startCopilotDeviceFlow() {
        copilotConnectionStatus = .untested
        isCopilotAuthenticating = true

        copilotAuthTask = Task {
            do {
                // Step 1: Get device code
                let code = try await appState.copilotAuthService.requestDeviceCode()
                deviceCode = code

                // Auto-open the verification URL
                if let url = URL(string: code.verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                // Auto-copy the user code
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                userCodeCopied = true

                // Step 2: Poll for authorization
                _ = try await appState.copilotAuthService.pollForAuthorization(deviceCode: code)

                // Step 3: Get a Copilot token to verify it works
                _ = try await appState.copilotAuthService.getCopilotToken()

                isCopilotAuthenticated = true
                isCopilotAuthenticating = false
                deviceCode = nil
                copilotConnectionStatus = .success
            } catch {
                isCopilotAuthenticating = false
                deviceCode = nil
                copilotConnectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelCopilotDeviceFlow() {
        copilotAuthTask?.cancel()
        copilotAuthTask = nil
        isCopilotAuthenticating = false
        deviceCode = nil
        copilotConnectionStatus = .untested
    }

    private func disconnectCopilot() {
        appState.copilotAuthService.signOut()
        isCopilotAuthenticated = false
        copilotConnectionStatus = .untested
    }

    // MARK: - Copilot Gateway Actions (Legacy)

    private func testCopilotConnection() async {
        appState.copilotAuthMethod = copilotAuthMethod
        if copilotAuthMethod == .externalGateway {
            appState.copilotGatewayURL = copilotGatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        }

        copilotConnectionStatus = .testing
        do {
            let ok = try await appState.copilotService.testConnection()
            copilotConnectionStatus = ok ? .success : .failed("Not reachable")
        } catch {
            copilotConnectionStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Project Fetching

    /// Resets the list and loads the first page using the current search query.
    /// If a project is already selected, it is pinned to the top of the list.
    private func fetchProjects() async {
        isLoadingProjects = true
        projectLoadError = nil
        projectStartAt = 0
        defer { isLoadingProjects = false }

        do {
            let result = try await appState.jiraService.fetchProjectsPage(
                query: projectSearch,
                startAt: 0
            )
            var projects = result.projects
            hasMoreProjects = !result.isLast
            projectStartAt = result.projects.count

            // If there is a pre-selected project, ensure it appears at the top.
            if !selectedProjectKey.isEmpty {
                if let idx = projects.firstIndex(where: { $0.key == selectedProjectKey }) {
                    // Already in the first page — move it to index 0.
                    let pinned = projects.remove(at: idx)
                    projects.insert(pinned, at: 0)
                } else if projectSearch.isEmpty {
                    // Not in the first page — fetch it individually and pin it.
                    if let pinned = try? await appState.jiraService.fetchProject(key: selectedProjectKey) {
                        projects.insert(pinned, at: 0)
                    }
                }
            }

            availableProjects = projects
        } catch {
            projectLoadError = error.localizedDescription
        }
    }

    /// Appends the next page to the existing list (triggered by scroll sentinel).
    private func loadMoreProjects() async {
        guard hasMoreProjects && !isFetchingMoreProjects && !isLoadingProjects else { return }
        isFetchingMoreProjects = true
        defer { isFetchingMoreProjects = false }

        do {
            let result = try await appState.jiraService.fetchProjectsPage(
                query: projectSearch,
                startAt: projectStartAt
            )
            availableProjects.append(contentsOf: result.projects)
            hasMoreProjects = !result.isLast
            projectStartAt += result.projects.count
        } catch {
            // Silently fail on pagination errors; user can use Refresh to retry.
        }
    }

    // MARK: - Jira Basic Auth Actions

    private func disconnectJiraBasicAuth() {
        jiraConnectedEmail = ""
        jiraAPIToken = ""
        jiraTokenPasted = false
        jiraConnectionStatus = .untested
        try? appState.keychainService.delete(
            service: KeychainService.jiraService,
            account: appState.jiraEmail
        )
    }

    // MARK: - Workspace Directory

    private func selectWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select Project Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
        }
    }
}
