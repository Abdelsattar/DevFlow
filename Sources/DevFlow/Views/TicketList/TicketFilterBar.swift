import SwiftUI

@MainActor
struct TicketFilterBar: View {
    @Environment(AppState.self) private var appState

    private var hasActiveFilters: Bool {
        !appState.searchText.isEmpty ||
        appState.filterComponentId != nil ||
        appState.filterStatus != nil ||
        appState.ticketScope != .currentSprint ||
        appState.assigneeFilter != .all
    }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 10) {
            searchField(searchText: $state.searchText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                filterControl(title: "Scope") {
                    Picker("Scope", selection: $state.ticketScope) {
                        ForEach(TicketScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                filterControl(title: "Assignee") {
                    Picker("Assignee", selection: $state.assigneeFilter) {
                        ForEach(AssigneeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                filterControl(title: "Component") {
                    if !appState.availableComponents.isEmpty {
                        Picker("Component", selection: $state.filterComponentId) {
                            Text("All Components").tag(nil as String?)
                            ForEach(appState.availableComponents) { component in
                                Text(component.name).tag(component.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    } else {
                        Text("All Components")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                filterControl(title: "Status") {
                    Picker("Status", selection: $state.filterStatus) {
                        Text("All Statuses").tag(nil as String?)
                        ForEach(appState.availableStatuses, id: \.self) { status in
                            Text(status).tag(status as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            HStack(spacing: 8) {
                Text("\(appState.filteredTickets.count) tickets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if appState.errorMessage != nil && appState.availableComponents.isEmpty {
                    Label("Components unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Failed to load components. Check your JIRA settings.")
                }

                Button("Reset") {
                    appState.searchText = ""
                    appState.filterComponentId = nil
                    appState.filterStatus = nil
                    appState.ticketScope = .currentSprint
                    appState.assigneeFilter = .all
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(!hasActiveFilters)
            }
        }
        .padding(10)
        .onChange(of: appState.ticketScope) { _, _ in
            Task {
                await appState.loadTickets()
            }
        }
        .onChange(of: appState.assigneeFilter) { _, _ in
            Task {
                await appState.loadTickets()
            }
        }
        .task {
            if appState.availableComponents.isEmpty {
                await appState.loadComponents()
            }
        }
    }

    @ViewBuilder
    private func searchField(searchText: Binding<String>) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tickets...", text: searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search tickets")
                .accessibilityHint("Filter tickets by keyword")

            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func filterControl<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            content()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
