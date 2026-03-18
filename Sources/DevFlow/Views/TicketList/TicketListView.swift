import SwiftUI

struct TicketListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            // MARK: - Sidebar (Ticket List)
            VStack(spacing: 0) {
                TicketFilterBar()

                Divider()

                if appState.isLoading && appState.tickets.isEmpty {
                    Spacer()
                    ProgressView("Loading tickets...")
                    Spacer()
                } else if appState.filteredTickets.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    List(appState.filteredTickets, selection: $state.selectedTicket) { ticket in
                        TicketRowView(ticket: ticket)
                            .tag(ticket)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 360, idealWidth: 420)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await appState.loadTickets() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                    .help("Refresh tickets")
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .help("Settings")
                }
            }
        } detail: {
            // MARK: - Detail Pane
            detailPane
        }
        .environment(appState)
        .task {
            if appState.tickets.isEmpty {
                await appState.loadTickets()
            }
        }
        .overlay(alignment: .bottom) {
            if let error = appState.errorMessage {
                errorBanner(error)
            }
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        let chatManager = appState.chatManager
        let hasSessions = !chatManager.sessions.isEmpty
        let hasActiveChat = chatManager.activeSession != nil

        if hasSessions {
            // Show chat tab bar + either the active chat or ticket detail
            VStack(spacing: 0) {
                ChatTabBar()

                Divider()

                if hasActiveChat, let session = chatManager.activeSession {
                    ChatView(session: session)
                } else if let ticket = appState.selectedTicket {
                    TicketDetailView(ticket: ticket)
                } else {
                    selectTicketPlaceholder
                }
            }
        } else if let ticket = appState.selectedTicket {
            TicketDetailView(ticket: ticket)
        } else {
            selectTicketPlaceholder
        }
    }

    // MARK: - Placeholder

    private var selectTicketPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a ticket")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose a ticket from the list to view details and start the workflow.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            if !appState.searchText.isEmpty || appState.filterComponentId != nil || appState.filterStatus != nil {
                Text("No matching tickets")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Try adjusting your filters.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(appState.ticketScope.emptyStateTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(appState.ticketScope.emptyStateMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Refresh") {
                        Task { await appState.loadTickets() }
                    }
                    .buttonStyle(.bordered)

                    Button("Re-run Setup") {
                        appState.isOnboardingComplete = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
        .padding()
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") {
                appState.errorMessage = nil
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(8)
        .background(.red.opacity(0.1))
        .cornerRadius(8)
        .padding(8)
    }
}
