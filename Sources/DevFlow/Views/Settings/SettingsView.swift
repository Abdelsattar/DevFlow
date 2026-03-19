import SwiftUI
import ServiceManagement

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            JiraSettingsView()
                .tabItem {
                    Label("JIRA", systemImage: "ticket")
                }

            GitHubSettingsView()
                .tabItem {
                    Label("GitHub", systemImage: "arrow.triangle.branch")
                }

            ComponentsSettingsView()
                .tabItem {
                    Label("Components", systemImage: "square.3.layers.3d")
                }

            CopilotSettingsView()
                .tabItem {
                    Label("Copilot", systemImage: "brain")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .environment(appState)
        .frame(width: 540, height: 450)
    }
}

// MARK: - General Settings

@MainActor
struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var workspacePath: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var launchError: String?
    @State private var showClearConfirmation: Bool = false
    @State private var showRestartSetupConfirmation: Bool = false
    @State private var sessionCount: Int = 0

    var body: some View {
        Form {
            Section("Workspace") {
                HStack {
                    TextField("Projects directory", text: $workspacePath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        selectDirectory()
                    }
                }

                Text("Local directory where repositories are cloned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch DevFlow at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                if let error = launchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Manage via System Settings > General > Login Items if needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Chat History") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved chat sessions")
                            .font(.body)
                        Text("\(sessionCount) session(s) stored. Sessions older than 30 days are automatically pruned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear All") {
                        showClearConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(sessionCount == 0)
                }
            }

            Section("Setup") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Setup Wizard")
                            .font(.body)
                        Text("Re-run the initial setup wizard to reconfigure JIRA, GitHub, Copilot, and workspace settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Restart Setup") {
                        showRestartSetupConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            workspacePath = appState.workspacePath
            launchAtLogin = SMAppService.mainApp.status == .enabled
            updateSessionCount()
        }
        .onChange(of: workspacePath) { _, newValue in
            appState.workspacePath = newValue
        }
        .alert("Clear All Chat History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllChatHistory()
            }
        } message: {
            Text("This will permanently delete all saved chat sessions and their message history. Active sessions will also be closed.")
        }
        .alert("Restart Setup Wizard?", isPresented: $showRestartSetupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart Setup", role: .destructive) {
                restartSetupWizard()
            }
        } message: {
            Text("This will take you back to the setup wizard so you can reconfigure all connections. Your existing settings will be pre-filled where possible.")
        }
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select Projects Directory"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchError = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchError = "Failed: \(error.localizedDescription)"
            // Revert toggle
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func updateSessionCount() {
        sessionCount = appState.chatManager.sessions.count
    }

    private func clearAllChatHistory() {
        // Close all active sessions
        let allSessions = appState.chatManager.sessions
        for session in allSessions {
            appState.chatManager.closeSession(session)
        }
        updateSessionCount()
    }

    private func restartSetupWizard() {
        appState.isOnboardingComplete = false
        // Close the Settings window — the main window will now show the wizard
        NSApp.keyWindow?.close()
    }
}
