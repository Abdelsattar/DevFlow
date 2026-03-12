import SwiftUI
import SwiftData
import AppKit

@main
struct DevFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private let appState = AppState.shared

    var body: some Scene {
        WindowGroup("DevFlow") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    delegate.appState = appState
                    appState.configurePersistence()
                    NotificationService.shared.requestPermission()
                }
        }
        .defaultSize(width: 700, height: 500)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

/// Manages the menu bar status item manually via NSStatusItem,
/// since MenuBarExtra with .window style is unreliable on macOS 26.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    private var statusItem: NSStatusItem?
    private var showAppMenuItem: NSMenuItem?
    private var resumeTicketMenuItem: NSMenuItem?
    private var startPlanMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "DevFlow")
        }

        let menu = NSMenu()

        let showApp = NSMenuItem(title: "Show DevFlow", action: #selector(showDevFlow), keyEquivalent: "")
        showApp.target = self
        menu.addItem(showApp)
        showAppMenuItem = showApp

        let resumeTicket = NSMenuItem(title: "Resume Last Ticket", action: #selector(resumeLastTicket), keyEquivalent: "")
        resumeTicket.target = self
        menu.addItem(resumeTicket)
        resumeTicketMenuItem = resumeTicket

        let startPlan = NSMenuItem(title: "Start Plan Chat", action: #selector(startPlanChat), keyEquivalent: "")
        startPlan.target = self
        menu.addItem(startPlan)
        startPlanMenuItem = startPlan

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        settingsMenuItem = settings

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit DevFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        updateMenuAvailability()
    }

    @objc private func showDevFlow() {
        openMainWindow()
    }

    @objc private func resumeLastTicket() {
        guard let appState else {
            openMainWindow()
            return
        }

        _ = appState.resumeLastActiveTicket()
        openMainWindow()
    }

    @objc private func startPlanChat() {
        guard let appState else {
            openMainWindow()
            return
        }

        _ = appState.startPlanChatFromQuickAction()
        openMainWindow()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "DevFlow" || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        updateMenuAvailability()
    }

    private func updateMenuAvailability() {
        showAppMenuItem?.isEnabled = true

        let hasTicketContext = (appState?.selectedTicket != nil) || (appState?.lastActiveTicketKey != nil)
        resumeTicketMenuItem?.isEnabled = hasTicketContext

        let canStartPlan = (appState?.selectedTicket != nil) ||
            (appState?.lastActiveTicketKey != nil) ||
            !(appState?.tickets.isEmpty ?? true)
        startPlanMenuItem?.isEnabled = canStartPlan

        settingsMenuItem?.isEnabled = true
    }
}
