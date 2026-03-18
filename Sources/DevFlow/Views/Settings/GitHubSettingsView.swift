import SwiftUI

struct GitHubSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var host: String = ""
    @State private var organization: String = ""
    @State private var orgSearch: String = ""
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
                let filtered = orgSearch.isEmpty
                    ? organizations
                    : organizations.filter { $0.login.localizedCaseInsensitiveContains(orgSearch) }
                let sorted = filtered.sorted { $0.login == organization && $1.login != organization }

                if organizations.count > 1 {
                    TextField("", text: $orgSearch, prompt: Text("Search organizations..."))
                        .textFieldStyle(.roundedBorder)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sorted) { org in
                            Button {
                                organization = org.login
                                appState.githubOrganization = org.login
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: organization == org.login ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(organization == org.login ? Color.accentColor : .secondary)
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
                                .background(organization == org.login ? Color.accentColor.opacity(0.08) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: min(CGFloat(organizations.count) * 44, 200))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                if !organization.isEmpty {
                    Label("\(organization) selected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
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
        Section("GitHub Host") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Host", text: $host, prompt: Text("github.com or github.your-company.com"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: host, initial: false) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                        let stripped: String
                        if trimmed.lowercased().hasPrefix("https://") {
                            stripped = String(trimmed.dropFirst(8))
                        } else if trimmed.lowercased().hasPrefix("http://") {
                            stripped = String(trimmed.dropFirst(7))
                        } else {
                            stripped = trimmed
                        }
                        if stripped != newValue { host = stripped }
                    }
                Text("Leave blank for github.com. Change this only if you use a GitHub Enterprise instance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Generate Token") {
            Button {
                let trimmedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                let effectiveHost = trimmedHost.isEmpty ? "github.com" : trimmedHost
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

            let displayHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty ? "github.com" : host
            Text("Opens \(displayHost) in your browser where you can create a token with the 'repo' scope.")
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
