import SwiftUI

@MainActor
struct ComponentsSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var availableComponents: [JiraComponent] = []
    @State private var selectedComponentIds: Set<String> = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var componentSearch: String = ""
    @State private var showSavedConfirmation: Bool = false

    var body: some View {
        Form {
            Section("Filter by Component") {
                Text("Optionally restrict your ticket list to specific project components. Leave all unchecked to show tickets from all components.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.jiraProjectKey.isEmpty {
                    Label("No projects configured. Set up projects in the JIRA settings tab first.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if availableComponents.isEmpty && !isLoading {
                    HStack {
                        if let error = loadError {
                            Label(error, systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                        } else {
                            Spacer()
                        }
                        Button("Fetch Components") {
                            Task { await fetchComponents() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading components...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("", text: $componentSearch, prompt: Text("Search components..."))
                        .textFieldStyle(.roundedBorder)

                    let filtered = componentSearch.isEmpty
                        ? availableComponents
                        : availableComponents.filter {
                            $0.name.localizedCaseInsensitiveContains(componentSearch) ||
                            ($0.description ?? "").localizedCaseInsensitiveContains(componentSearch)
                        }

                    ForEach(filtered) { component in
                        Toggle(isOn: Binding(
                            get: { selectedComponentIds.contains(component.id) },
                            set: { isOn in
                                if isOn { selectedComponentIds.insert(component.id) }
                                else { selectedComponentIds.remove(component.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name)
                                if let desc = component.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !selectedComponentIds.isEmpty {
                        Label("\(selectedComponentIds.count) component(s) selected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Button("Refresh") {
                        Task { await fetchComponents() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if availableComponents.isEmpty && !appState.jiraProjectKey.isEmpty {
                Task { await fetchComponents() }
            }
        }
    }

    // MARK: - Actions

    private func fetchComponents() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let components = try await appState.jiraService.fetchComponents(project: appState.jiraProjectKey)
            availableComponents = components
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        withAnimation { showSavedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedConfirmation = false }
        }
    }
}
