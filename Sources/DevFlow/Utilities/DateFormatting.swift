import Foundation

/// Utility for parsing and formatting dates from JIRA API responses.
enum DateFormatting: Sendable {
    // MARK: - ISO 8601 Parser

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// JIRA sometimes uses a non-standard format: "2021-01-17T12:34:00.000+0000"
    private static let jiraFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Relative Date Formatter

    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Public API

    /// Parse a JIRA date string into a Date.
    static func parse(_ dateString: String) -> Date? {
        if let date = isoFormatter.date(from: dateString) {
            return date
        }
        if let date = isoFormatterNoFractional.date(from: dateString) {
            return date
        }
        return jiraFormatter.date(from: dateString)
    }

    /// Format a JIRA date string as a relative date ("2h ago", "Yesterday").
    static func relativeDate(from dateString: String) -> String {
        guard let date = parse(dateString) else {
            return dateString
        }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Format a JIRA date string as a short date ("Jan 17, 2021").
    static func shortDate(from dateString: String) -> String {
        guard let date = parse(dateString) else {
            return dateString
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Format a JIRA date string as date and time ("Jan 17, 2021, 12:34 PM").
    static func dateAndTime(from dateString: String) -> String {
        guard let date = parse(dateString) else {
            return dateString
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
