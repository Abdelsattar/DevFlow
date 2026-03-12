import Foundation

// MARK: - ADF Document

/// Atlassian Document Format - used for JIRA descriptions and comment bodies.
/// See: https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/
struct ADFDocument: Codable, Sendable {
    let type: String        // Always "doc"
    let version: Int?       // Always 1
    let content: [ADFNode]?

    /// Convert ADF document to plain text for display and AI context.
    func toPlainText() -> String {
        guard let content else { return "" }
        return content.map { $0.toPlainText() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ADF Node

struct ADFNode: Codable, Sendable {
    let type: String
    let text: String?
    let content: [ADFNode]?
    let marks: [ADFMark]?
    let attrs: ADFAttrs?

    func toPlainText() -> String {
        switch type {
        // Inline nodes
        case "text":
            return text ?? ""
        case "hardBreak":
            return "\n"
        case "mention":
            return attrs?.text ?? ""
        case "emoji":
            return attrs?.text ?? attrs?.shortName ?? ""
        case "inlineCard":
            return attrs?.url ?? ""
        case "date":
            return attrs?.timestamp ?? ""
        case "status":
            return "[\(attrs?.text ?? "")]"

        // Block nodes - horizontal rule
        case "rule":
            return "\n---\n"

        // Block nodes with content
        case "paragraph":
            let childText = content?.map { $0.toPlainText() }.joined() ?? ""
            return childText + "\n"

        case "heading":
            let level = attrs?.level ?? 1
            let prefix = String(repeating: "#", count: level) + " "
            let childText = content?.map { $0.toPlainText() }.joined() ?? ""
            return prefix + childText + "\n"

        case "codeBlock":
            let lang = attrs?.language ?? ""
            let childText = content?.map { $0.toPlainText() }.joined() ?? ""
            return "```\(lang)\n\(childText)\n```\n"

        case "blockquote":
            let childText = content?.map { $0.toPlainText() }.joined() ?? ""
            let lines = childText.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.map { "> \($0)" }.joined(separator: "\n") + "\n"

        case "bulletList":
            return content?.map { node in
                let text = node.toPlainText().trimmingCharacters(in: .newlines)
                return "- \(text)\n"
            }.joined() ?? ""

        case "orderedList":
            return content?.enumerated().map { index, node in
                let text = node.toPlainText().trimmingCharacters(in: .newlines)
                return "\(index + 1). \(text)\n"
            }.joined() ?? ""

        case "listItem":
            return content?.map { $0.toPlainText() }.joined() ?? ""

        case "table":
            return content?.map { $0.toPlainText() }.joined() ?? ""

        case "tableRow":
            let cells = content?.map { $0.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
            return "| " + cells.joined(separator: " | ") + " |\n"

        case "tableHeader", "tableCell":
            return content?.map { $0.toPlainText() }.joined() ?? ""

        case "panel":
            let childText = content?.map { $0.toPlainText() }.joined() ?? ""
            let panelType = attrs?.panelType ?? "info"
            return "[\(panelType.uppercased())] \(childText)"

        case "expand":
            let title = attrs?.title ?? "Details"
            let childText = content?.map { $0.toPlainText() }.joined() ?? ""
            return "\(title):\n\(childText)"

        case "mediaSingle", "mediaGroup", "media":
            return "[attachment]\n"

        default:
            // Unknown node type - recurse into children
            return content?.map { $0.toPlainText() }.joined() ?? ""
        }
    }
}

// MARK: - ADF Mark

struct ADFMark: Codable, Sendable {
    let type: String         // "strong", "em", "code", "link", etc.
    let attrs: ADFMarkAttrs?
}

struct ADFMarkAttrs: Codable, Sendable {
    let href: String?
    let title: String?
    let color: String?
    let type: String?        // For subsup: "sub" or "sup"
}

// MARK: - ADF Attrs

/// Flexible attributes for ADF nodes. Different node types use different attrs.
struct ADFAttrs: Codable, Sendable {
    // heading
    let level: Int?

    // codeBlock
    let language: String?

    // mention
    let id: String?
    let text: String?

    // emoji
    let shortName: String?

    // inlineCard
    let url: String?

    // date
    let timestamp: String?

    // status
    let color: String?

    // panel
    let panelType: String?

    // expand
    let title: String?

    // media
    let type: String?
    let width: Int?
    let layout: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(Int.self, forKey: .level)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        panelType = try container.decodeIfPresent(String.self, forKey: .panelType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
    }

    private enum CodingKeys: String, CodingKey {
        case level, language, id, text, shortName, url, timestamp, color
        case panelType, title, type, width, layout
    }
}
