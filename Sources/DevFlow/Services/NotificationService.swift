import Foundation
import UserNotifications

/// Desktop notification service for DevFlow events.
/// Uses UNUserNotificationCenter to send local notifications
/// for PR creation, commits, and errors — critical for a menu bar
/// app where the user may not see the popover.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    // MARK: - Permission

    /// Request notification permissions. Safe to call multiple times.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Permission result is handled silently
        }
    }

    // MARK: - PR Created

    /// Notify the user that a pull request was created.
    func notifyPRCreated(ticketKey: String, prNumber: Int, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "Pull Request Created"
        content.body = "\(ticketKey): PR #\(prNumber) created successfully."
        content.subtitle = prURL
        content.sound = .default

        send(content, identifier: "pr-created-\(ticketKey)-\(prNumber)")
    }

    // MARK: - Commit Done

    /// Notify the user that changes were committed.
    func notifyCommitDone(ticketKey: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Changes Committed"
        content.body = "\(ticketKey): \(message)"
        content.sound = .default

        send(content, identifier: "commit-done-\(ticketKey)-\(UUID().uuidString.prefix(8))")
    }

    // MARK: - Error

    /// Notify the user of a significant error.
    func notifyError(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .defaultCritical

        send(content, identifier: "error-\(UUID().uuidString.prefix(8))")
    }

    // MARK: - JIRA Transition

    /// Notify the user that a JIRA ticket was transitioned.
    func notifyJiraTransition(ticketKey: String, newStatus: String) {
        let content = UNMutableNotificationContent()
        content.title = "Ticket Updated"
        content.body = "\(ticketKey) moved to '\(newStatus)'."
        content.sound = .default

        send(content, identifier: "jira-transition-\(ticketKey)")
    }

    // MARK: - Autonomous Flow

    /// Notify the user that an autonomous flow completed successfully.
    func notifyAutonomousFlowComplete(ticketKey: String, prNumber: Int, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "Autonomous Flow Complete"
        content.body = "\(ticketKey): PR #\(prNumber) created successfully."
        content.subtitle = prURL
        content.sound = .default

        send(content, identifier: "auto-flow-done-\(ticketKey)")
    }

    /// Notify the user that an autonomous flow failed.
    func notifyAutonomousFlowFailed(ticketKey: String, stage: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Autonomous Flow Failed"
        content.body = "\(ticketKey) failed at '\(stage)': \(error)"
        content.sound = .defaultCritical

        send(content, identifier: "auto-flow-failed-\(ticketKey)")
    }

    /// Notify the user that an autonomous flow is paused pending approval.
    func notifyAutonomousFlowPaused(ticketKey: String, stage: String) {
        let content = UNMutableNotificationContent()
        content.title = "Approval Needed"
        content.body = "\(ticketKey): Autonomous flow paused at '\(stage)'. Open DevFlow to review and approve."
        content.sound = .default

        send(content, identifier: "auto-flow-paused-\(ticketKey)")
    }

    // MARK: - Private

    private func send(_ content: UNNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                // Log but don't crash — notifications are best-effort
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
