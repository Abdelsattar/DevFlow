import SwiftUI

@MainActor
struct JiraSettingsView: View {
    @Environment(AppState.self) private var appState

    // Auth method picker
    @State private var authMethod: JiraAuthMethod = .basicAuth

    // Basic Auth fields
    @State private var baseURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var projectKeyText: String = ""

    // OAuth fields
    @State private var oauthClientId: String = ""
    @State private var isOAuthConnected: Bool = false
    @State private var oauthCloudName: String = ""
    @State private var isAuthenticating: Bool = false

    // Shared state
    @State private var connectionStatus: ConnectionStatus = .untested
    @State private var isTesting: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSavedConfirmation: Bool = false
    @State private var isRefreshing: Bool = false

    var body: some View {
        Form {
            Section("Authentication Method") {
                Picker("Method", selection: $authMethod) {
                    Text("OAuth 2.0 (Recommended)").tag(JiraAuthMethod.oauth)
                    Text("Basic Auth (API Token)").tag(JiraAuthMethod.basicAuth)
                }
                .pickerStyle(.segmented)
                .onChange(of: authMethod) { _, newValue in
                    appState.jiraAuthMethod = newValue
                    connectionStatus = .untested
                }
            }

            if authMethod == .oauth {
                oauthSection
            } else {
                basicAuthSection
            }

            Section("Project") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $projectKeyText, prompt: Text("PROJ"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
                Text("The JIRA project key whose tickets will be shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if isRefreshing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Refreshing tickets...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if showSavedConfirmation {
                        Label("Saved — tickets reloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    Spacer()

                    Button("Save") {
                        Task { await saveAndRefresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isRefreshing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadSettings() }
    }

    // MARK: - OAuth Section

    @ViewBuilder
    private var oauthSection: some View {
        Section("Atlassian OAuth 2.0") {
            if isOAuthConnected {
                // Connected state
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Connected to \(oauthCloudName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !appState.jiraBaseURL.isEmpty {
                            Text(appState.jiraBaseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Disconnect") {
                        disconnect()
                    }
                    .foregroundStyle(.red)
                }
            } else {
                // Not connected state
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OAuth Client ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $oauthClientId, prompt: Text("Your Atlassian OAuth 2.0 Client ID"))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                    }

                    HStack {
                        connectionStatusBadge
                        Spacer()
                        Button("Sign in with Atlassian") {
                            Task { await signInWithOAuth() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(oauthClientId.isEmpty || isAuthenticating)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
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
    }

    // MARK: - Basic Auth Section

    @ViewBuilder
    private var basicAuthSection: some View {
        Section("JIRA Cloud Connection") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $baseURL, prompt: Text("https://yourcompany.atlassian.net"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                if !baseURL.isEmpty && !isValidURL(baseURL) {
                    Label("Please enter a valid URL (e.g. https://yourcompany.atlassian.net)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Email")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $email, prompt: Text("you@company.com"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                if !email.isEmpty && !isValidEmail(email) {
                    Label("Please enter a valid email address", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("", text: $apiToken, prompt: Text("Your JIRA API token"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
            }

            HStack {
                connectionStatusBadge
                Spacer()
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(isTesting || baseURL.isEmpty || email.isEmpty || apiToken.isEmpty)
            }
        }
    }

    // MARK: - Connection Status Badge

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch connectionStatus {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(isAuthenticating ? "Authenticating..." : "Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Validation

    private var canSave: Bool {
        if authMethod == .oauth {
            return isOAuthConnected || !oauthClientId.isEmpty
        } else {
            return !baseURL.isEmpty && !email.isEmpty && !apiToken.isEmpty
                && isValidURL(baseURL) && isValidEmail(email)
        }
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme,
              !scheme.isEmpty,
              url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func isValidEmail(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "@")
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".") else { return false }
        return true
    }

    // MARK: - Actions

    private func loadSettings() {
        authMethod = appState.jiraAuthMethod
        baseURL = appState.jiraBaseURL
        email = appState.jiraEmail
        projectKeyText = appState.jiraProjectKey
        oauthClientId = appState.jiraOAuthClientId
        isOAuthConnected = appState.jiraOAuthService.isAuthenticated
        oauthCloudName = appState.jiraCloudName

        if !email.isEmpty {
            if let token = try? appState.keychainService.retrieve(
                service: KeychainService.jiraService,
                account: email
            ) {
                apiToken = token
            }
        }
    }

    private func save() {
        appState.jiraAuthMethod = authMethod

        if authMethod == .oauth {
            appState.jiraOAuthClientId = oauthClientId.trimmingCharacters(in: .whitespaces)
        } else {
            appState.jiraBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            appState.jiraEmail = email.trimmingCharacters(in: .whitespaces)

            let keys = projectKeyText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter { !$0.isEmpty }
            appState.jiraProjectKey = keys.first ?? ""

            do {
                try appState.keychainService.saveOrUpdate(
                    service: KeychainService.jiraService,
                    account: appState.jiraEmail,
                    token: apiToken
                )
            } catch {
                connectionStatus = .failed("Failed to save token: \(error.localizedDescription)")
                return
            }
        }

        // Save project key for both auth methods
        let keys = projectKeyText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        appState.jiraProjectKey = keys.first ?? ""
    }

    private func saveAndRefresh() async {
        save()
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await appState.loadTickets() }
            group.addTask { await appState.loadComponents() }
        }
        withAnimation { showSavedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showSavedConfirmation = false }
        }
    }

    private func signInWithOAuth() async {
        appState.jiraOAuthClientId = oauthClientId.trimmingCharacters(in: .whitespaces)
        connectionStatus = .testing
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await appState.jiraOAuthService.authenticate()
            isOAuthConnected = true
            oauthCloudName = appState.jiraCloudName
            connectionStatus = .success
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func disconnect() {
        appState.jiraOAuthService.signOut()
        isOAuthConnected = false
        oauthCloudName = ""
        connectionStatus = .untested
    }

    private func testConnection() async {
        save()

        connectionStatus = .testing
        isTesting = true
        defer { isTesting = false }

        do {
            let success = try await appState.jiraService.testConnection()
            connectionStatus = success ? .success : .failed("Connection failed")
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Connection Status Enum

enum ConnectionStatus: Equatable {
    case untested
    case testing
    case success
    case failed(String)
}
