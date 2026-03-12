import SwiftUI

struct TicketFilterBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tickets...", text: $state.searchText)
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
            .cornerRadius(8)

            // Filter chips
            HStack(spacing: 8) {
                Picker("Scope", selection: $state.ticketScope) {
                    ForEach(TicketScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                // Assignee filter
                Picker("Assignee", selection: $state.assigneeFilter) {
                    ForEach(AssigneeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                // Component filter (client-side)
                if !appState.availableComponents.isEmpty {
                    Picker("Component", selection: $state.filterComponentId) {
                        Text("All Components").tag(nil as String?)
                        ForEach(appState.availableComponents) { component in
                            Text(component.name).tag(component.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                } else if appState.errorMessage != nil {
                    Label("Components unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Failed to load components. Check your JIRA settings.")
                }

                // Status filter (client-side)
                Picker("Status", selection: $state.filterStatus) {
                    Text("All Statuses").tag(nil as String?)
                    Text("To Do").tag("To Do" as String?)
                    Text("In Progress").tag("In Progress" as String?)
                    Text("In Review").tag("In Review" as String?)
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                Spacer()

                // Ticket count
                Text("\(appState.filteredTickets.count) tickets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
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
}
