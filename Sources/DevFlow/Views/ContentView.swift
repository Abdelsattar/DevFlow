import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isOnboardingComplete {
                TicketListView()
            } else {
                SetupWizardView()
            }
        }
        .environment(appState)
    }
}
