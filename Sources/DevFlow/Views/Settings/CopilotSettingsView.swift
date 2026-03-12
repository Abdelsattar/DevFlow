import SwiftUI
import AppKit

struct CopilotSettingsView: View {
    @Environment(AppState.self) private var appState

    // Auth method
    @State private var authMethod: CopilotAuthMethod = .oauthDeviceFlow

    // OAuth Device Flow state
    @State private var isAuthenticated: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var deviceCode: DeviceCodeResponse?
    @State private var userCodeCopied: Bool = false
    @State private var authTask: Task<Void, Never>?

    // External gateway state (legacy)
    @State private var gatewayURL: String = ""

    // Shared
    @State private var connectionStatus: ConnectionStatus = .untested
    @State private var isTesting: Bool = false
    @State private var showSavedConfirmation: Bool = false

    var body: some View {
        Form {
            Section("Authentication Method") {
                Picker("Method", selection: $authMethod) {
                    Text("GitHub Copilot (Recommended)").tag(CopilotAuthMethod.oauthDeviceFlow)
                    Text("External Gateway").tag(CopilotAuthMethod.externalGateway)
                }
                .pickerStyle(.segmented)
                .onChange(of: authMethod) { _, newValue in
                    appState.copilotAuthMethod = newValue
                    connectionStatus = .untested
                }
            }

            if authMethod == .oauthDeviceFlow {
                oauthSection
            } else {
                gatewaySection
            }

            Section {
                HStack {
                    if showSavedConfirmation {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    connectionStatusBadge

                    Spacer()

                    if authMethod == .externalGateway {
                        Button("Test Connection") {
                            Task { await testConnection() }
                        }
                        .disabled(isTesting || gatewayURL.isEmpty || !isValidGatewayURL(gatewayURL))
                    }

                    if authMethod == .externalGateway {
                        Button("Save") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gatewayURL.isEmpty || !isValidGatewayURL(gatewayURL))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadSettings() }
        .onDisappear { authTask?.cancel() }
    }

    // MARK: - OAuth Device Flow Section

    @ViewBuilder
    private var oauthSection: some View {
        Section("GitHub Copilot Authentication") {
            if isAuthenticated {
                // Connected state
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Connected to GitHub Copilot", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Using your GitHub Copilot subscription directly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect") {
                        disconnect()
                    }
                    .foregroundStyle(.red)
                }

                // Test connection button for connected state
                HStack {
                    connectionStatusBadge
                    Spacer()
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting)
                }
            } else if let deviceCode, isAuthenticating {
                // Device code display
                deviceCodeView(deviceCode)
            } else {
                // Sign in prompt
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign in with your GitHub account to use Copilot directly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("No external tools or npm packages required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .failed(let msg) = connectionStatus {
                        Label(msg, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Spacer()
                        Button("Sign in with GitHub") {
                            startDeviceFlow()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAuthenticating)
                    }
                }
            }
        }

        Section("Requirements") {
            VStack(alignment: .leading, spacing: 4) {
                Label("Active GitHub Copilot subscription", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("GitHub.com account (not Enterprise)", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Device Code View

    @ViewBuilder
    private func deviceCodeView(_ code: DeviceCodeResponse) -> some View {
        VStack(spacing: 16) {
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
                cancelDeviceFlow()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - External Gateway Section (Legacy)

    @ViewBuilder
    private var gatewaySection: some View {
        Section("Copilot API Gateway") {
            TextField("Gateway URL", text: $gatewayURL, prompt: Text("http://localhost:3030/v1"))
                .textFieldStyle(.roundedBorder)

            if !gatewayURL.isEmpty && !isValidGatewayURL(gatewayURL) {
                Label("Please enter a valid URL (e.g. http://localhost:3030/v1)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Section("Setup Instructions") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The external gateway provides an OpenAI-compatible endpoint using your GitHub Copilot subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Quick Setup:")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("1. Install: npm install -g copilot-api")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("2. Start: copilot-api start")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("3. The gateway runs at http://localhost:3030/v1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Testing...")
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
                .lineLimit(2)
        }
    }

    // MARK: - Validation

    private func isValidGatewayURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme,
              !scheme.isEmpty,
              url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: - Actions

    private func loadSettings() {
        authMethod = appState.copilotAuthMethod
        gatewayURL = appState.copilotGatewayURL
        isAuthenticated = appState.copilotAuthService.isAuthenticated
    }

    private func save() {
        appState.copilotAuthMethod = authMethod
        if authMethod == .externalGateway {
            appState.copilotGatewayURL = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        }
        showSaveConfirmation()
    }

    private func startDeviceFlow() {
        connectionStatus = .untested
        isAuthenticating = true

        authTask = Task {
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

                isAuthenticated = true
                isAuthenticating = false
                deviceCode = nil
                connectionStatus = .success
            } catch {
                isAuthenticating = false
                deviceCode = nil
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelDeviceFlow() {
        authTask?.cancel()
        authTask = nil
        isAuthenticating = false
        deviceCode = nil
        connectionStatus = .untested
    }

    private func disconnect() {
        appState.copilotAuthService.signOut()
        isAuthenticated = false
        connectionStatus = .untested
    }

    private func testConnection() async {
        save()
        connectionStatus = .testing
        isTesting = true
        defer { isTesting = false }

        do {
            let success = try await appState.copilotService.testConnection()
            connectionStatus = success ? .success : .failed("Not reachable")
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func showSaveConfirmation() {
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
