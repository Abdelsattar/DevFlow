import SwiftUI

struct GitHubSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var host: String = ""
    @State private var organization: String = ""
    @State private var pat: String = ""
    @State private var connectionStatus: ConnectionStatus = .untested
    @State private var isValidating: Bool = false
    @State private var connectedUser: GitHubUser?
    @State private var organizations: [GitHubOrganization] = []
    @State private var showSavedConfirmation: Bool = false

    var body: some View {
        Form {
            if let user = connectedUser {
                connectedSection(user: user)
            } else {
                setupSection
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadSettings() }
    }

    // MARK: - Connected State

    @ViewBuilder
    private func connectedSection(user: GitHubUser) -> some View {
        Section("Connection") {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected as \(user.name ?? user.login)")
                        .fontWeight(.medium)
                    Text("@\(user.login) on \(host)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Disconnect") {
                    disconnect()
                }
                .foregroundStyle(.red)
            }
        }

        if !organizations.isEmpty {
            Section("Organization") {
                if organizations.count == 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                            .foregroundStyle(.secondary)
                        Text(organizations[0].login)
                            .fontWeight(.medium)
                    }
                } else {
                    Picker("Organization", selection: $organization) {
                        Text("Select an organization").tag("")
                        ForEach(organizations) { org in
                            Text(org.login).tag(org.login)
                        }
                    }
                    .onChange(of: organization) { _, newValue in
                        appState.githubOrganization = newValue
                    }
                }
            }
        }

        Section {
            HStack {
                if showSavedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Setup State

    @ViewBuilder
    private var setupSection: some View {
        Section("Connect to GitHub Enterprise") {
            Button {
                let trimmedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                if let url = URL(string: "https://\(trimmedHost)/settings/tokens/new?scopes=repo&description=DevFlow") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Generate Token on GitHub")
                }
            }
            .buttonStyle(.borderedProminent)

            Text("Opens \(host) where you can generate a token with 'repo' scope.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Paste Token") {
            SecureField("Personal Access Token", text: $pat, prompt: Text("Paste your token here"))
                .textFieldStyle(.roundedBorder)

            HStack {
                connectionStatusView
                Spacer()
                Button("Verify Token") {
                    Task { await validateToken() }
                }
                .disabled(pat.isEmpty || isValidating)
            }
        }

        Section("Advanced") {
            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Enterprise Host")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Host", text: $host, prompt: Text("github.your-company.com"))
                    .textFieldStyle(.roundedBorder)
            }

            Text("Only change this if your GitHub Enterprise is on a different host.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Verifying...")
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

    // MARK: - Actions

    private func loadSettings() {
        host = appState.githubHost
        organization = appState.githubOrganization

        if !host.isEmpty {
            if let token = try? appState.keychainService.retrieve(
                service: KeychainService.githubService,
                account: host
            ) {
                pat = token
                // If we have a saved token, validate it to show connected state
                Task { await validateToken() }
            }
        }
    }

    private func validateToken() async {
        appState.githubHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        try? appState.keychainService.saveOrUpdate(
            service: KeychainService.githubService,
            account: appState.githubHost,
            token: pat
        )

        connectionStatus = .testing
        isValidating = true
        defer { isValidating = false }

        do {
            let (user, orgs) = try await appState.githubService.validateTokenAndGetInfo()
            connectedUser = user
            organizations = orgs
            connectionStatus = .success

            if orgs.count == 1 {
                organization = orgs[0].login
                appState.githubOrganization = orgs[0].login
            }
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func disconnect() {
        connectedUser = nil
        organizations = []
        pat = ""
        organization = ""
        connectionStatus = .untested
        try? appState.keychainService.delete(
            service: KeychainService.githubService,
            account: appState.githubHost
        )
    }

    private func save() {
        appState.githubHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        appState.githubOrganization = organization.trimmingCharacters(in: .whitespaces)

        if !pat.isEmpty {
            try? appState.keychainService.saveOrUpdate(
                service: KeychainService.githubService,
                account: appState.githubHost,
                token: pat
            )
        }

        withAnimation {
            showSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedConfirmation = false
            }
        }
    }
}
