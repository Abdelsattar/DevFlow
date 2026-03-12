import SwiftUI

struct TicketRowView: View {
    let ticket: JiraTicket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Key + Priority
            HStack {
                Text(ticket.key)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)

                Spacer()

                if let priority = ticket.fields.priority {
                    Image(systemName: priority.icon)
                        .font(.caption)
                        .foregroundStyle(priorityColor(priority.name))
                        .help(priority.name)
                        .accessibilityLabel("Priority: \(priority.name)")
                }

                if let issueType = ticket.fields.issuetype {
                    Image(systemName: issueType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(issueType.name)
                        .accessibilityLabel("Type: \(issueType.name)")
                }
            }

            // Summary
            Text(ticket.fields.summary)
                .font(.body)
                .lineLimit(2)

            // Bottom row: Status badge + Components
            HStack(spacing: 6) {
                statusBadge(ticket.fields.status)

                ForEach(ticket.fields.components.prefix(2)) { component in
                    Text(component.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .cornerRadius(4)
                        .accessibilityLabel("Component: \(component.name)")
                }

                Spacer()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ticket.key): \(ticket.fields.summary), status \(ticket.fields.status.name)")
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: JiraStatus) -> some View {
        Text(status.name)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusBackgroundColor(status))
            .foregroundStyle(statusForegroundColor(status))
            .cornerRadius(4)
    }

    private func statusBackgroundColor(_ status: JiraStatus) -> Color {
        switch status.color {
        case .gray:   return .secondary.opacity(0.2)
        case .blue:   return .blue.opacity(0.2)
        case .orange: return .orange.opacity(0.2)
        case .green:  return .green.opacity(0.2)
        }
    }

    private func statusForegroundColor(_ status: JiraStatus) -> Color {
        switch status.color {
        case .gray:   return .secondary
        case .blue:   return .blue
        case .orange: return .orange
        case .green:  return .green
        }
    }

    private func priorityColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "highest", "critical", "blocker": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .blue
        case "lowest": return .secondary
        default: return .secondary
        }
    }
}
