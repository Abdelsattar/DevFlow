import Foundation

/// Parses fenced code blocks from AI-generated markdown responses and
/// extracts file paths and content. Handles multiple common formats:
///
/// Format 1: File path on the line before the code block
/// ```
/// **`src/foo.swift`**
/// ```swift
/// code here
/// ```
///
/// Format 2: File path in the code fence info string
/// ```swift:src/foo.swift
/// code here
/// ```
///
/// Format 3: File path comment inside the code block
/// ```swift
/// // File: src/foo.swift
/// code here
/// ```
enum CodeBlockParser {

    /// A raw parsed code block before it becomes a FileChange.
    struct ParsedBlock: Sendable {
        let filePath: String?
        let language: String
        let content: String
        let changeType: FileChangeType
    }

    // MARK: - Public API

    /// Extract all code blocks from a markdown string and convert them to FileChanges.
    static func extractFileChanges(from markdown: String) -> [FileChange] {
        let blocks = parseCodeBlocks(from: markdown)
        return blocks.compactMap { block -> FileChange? in
            guard let path = block.filePath, !path.isEmpty else { return nil }
            return FileChange(
                filePath: path,
                language: block.language,
                changeType: block.changeType,
                content: block.content
            )
        }
    }

    /// Parse all fenced code blocks from markdown, attempting to identify
    /// file paths for each.
    static func parseCodeBlocks(from markdown: String) -> [ParsedBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [ParsedBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Look for opening fence: ``` or ~~~
            if isFenceOpener(line) {
                let fenceInfo = extractFenceInfo(line)
                let language = fenceInfo.language
                let fenceFilePath = fenceInfo.filePath

                // Collect content lines until closing fence
                var contentLines: [String] = []
                i += 1
                while i < lines.count && !isFenceCloser(lines[i]) {
                    contentLines.append(lines[i])
                    i += 1
                }
                // Skip closing fence
                if i < lines.count { i += 1 }

                // Try to find file path from multiple sources
                let (filePath, cleanedContent) = resolveFilePath(
                    fencePath: fenceFilePath,
                    contextLines: contextLinesBefore(lines: lines, fenceLineIndex: i - contentLines.count - 2),
                    contentLines: contentLines
                )

                let changeType = inferChangeType(
                    contextLines: contextLinesBefore(lines: lines, fenceLineIndex: i - contentLines.count - 2),
                    filePath: filePath
                )

                blocks.append(ParsedBlock(
                    filePath: filePath,
                    language: language,
                    content: cleanedContent,
                    changeType: changeType
                ))
            } else {
                i += 1
            }
        }

        return blocks
    }

    // MARK: - Fence Detection

    private static func isFenceOpener(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func isFenceCloser(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "```" || trimmed == "~~~"
    }

    // MARK: - Fence Info Parsing

    private struct FenceInfo {
        let language: String
        let filePath: String?
    }

    /// Parse the info string after ``` (e.g., `swift:src/foo.swift` or just `swift`).
    private static func extractFenceInfo(_ line: String) -> FenceInfo {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let afterFence: String
        if trimmed.hasPrefix("```") {
            afterFence = String(trimmed.dropFirst(3))
        } else if trimmed.hasPrefix("~~~") {
            afterFence = String(trimmed.dropFirst(3))
        } else {
            return FenceInfo(language: "", filePath: nil)
        }

        // Check for language:filepath format
        if afterFence.contains(":") {
            let parts = afterFence.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let lang = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if looksLikeFilePath(path) {
                    return FenceInfo(language: lang, filePath: path)
                }
            }
        }

        // Check if the whole info string is a file path (rare)
        if looksLikeFilePath(afterFence) && !isLanguageName(afterFence) {
            let ext = (afterFence as NSString).pathExtension
            return FenceInfo(language: languageFromExtension(ext), filePath: afterFence)
        }

        // Just a language name
        return FenceInfo(
            language: afterFence.trimmingCharacters(in: .whitespaces),
            filePath: nil
        )
    }

    // MARK: - File Path Resolution

    /// Try to find the file path from multiple sources: fence info, preceding
    /// context lines, or a comment inside the code block.
    private static func resolveFilePath(
        fencePath: String?,
        contextLines: [String],
        contentLines: [String]
    ) -> (filePath: String?, content: String) {
        // 1. Fence info path (highest priority)
        if let path = fencePath, !path.isEmpty {
            return (path, contentLines.joined(separator: "\n"))
        }

        // 2. Check context lines before the code block for a file path
        for contextLine in contextLines.reversed() {
            if let path = extractFilePathFromContextLine(contextLine) {
                return (path, contentLines.joined(separator: "\n"))
            }
        }

        // 3. Check first 1-2 lines of content for a file path comment
        for lineIndex in 0..<min(2, contentLines.count) {
            if let path = extractFilePathFromComment(contentLines[lineIndex]) {
                // Remove the file path comment from content
                var cleaned = contentLines
                cleaned.remove(at: lineIndex)
                return (path, cleaned.joined(separator: "\n"))
            }
        }

        // No file path found
        return (nil, contentLines.joined(separator: "\n"))
    }

    /// Get up to 3 non-empty lines before the fence opener for context.
    private static func contextLinesBefore(lines: [String], fenceLineIndex: Int) -> [String] {
        var result: [String] = []
        var idx = fenceLineIndex - 1
        while idx >= 0 && result.count < 3 {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                result.append(line)
            }
            idx -= 1
        }
        return result
    }

    /// Extract a file path from a context line like:
    /// - `**src/foo.swift**`
    /// - `**`src/foo.swift`**`
    /// - `File: src/foo.swift`
    /// - `### src/foo.swift`
    /// - `src/foo.swift:`
    private static func extractFilePathFromContextLine(_ line: String) -> String? {
        var cleaned = line

        // Strip markdown bold/italic/backtick wrappers
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // Strip leading markdown heading markers
        while cleaned.hasPrefix("#") {
            cleaned = String(cleaned.dropFirst())
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // Strip common prefixes
        let prefixes = ["File:", "file:", "Path:", "path:", "Filename:", "filename:",
                        "Create file:", "Modify file:", "New file:", "Update file:",
                        "Create:", "Modify:", "New:", "Update:", "Delete:"]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Strip trailing colon
        if cleaned.hasSuffix(":") {
            cleaned = String(cleaned.dropLast())
                .trimmingCharacters(in: .whitespaces)
        }

        // Strip trailing parenthetical annotations like "(new file)", "(modify)", "(create)", etc.
        if let parenRange = cleaned.range(of: #"\s*\(.*\)\s*$"#, options: .regularExpression) {
            cleaned = String(cleaned[cleaned.startIndex..<parenRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }

        // Check if what remains looks like a file path
        if looksLikeFilePath(cleaned) {
            return cleaned
        }

        return nil
    }

    /// Extract a file path from a comment line inside the code block.
    /// E.g.: `// File: src/foo.swift` or `# File: src/foo.swift`
    private static func extractFilePathFromComment(_ line: String) -> String? {
        var cleaned = line.trimmingCharacters(in: .whitespaces)

        // Strip comment prefixes
        let commentPrefixes = ["//", "#", "--", "/*", "<!--", ";;", "rem "]
        for prefix in commentPrefixes {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Check for "File:" prefix
        let filePrefixes = ["File:", "file:", "Path:", "path:", "Filename:", "filename:"]
        for prefix in filePrefixes {
            if cleaned.hasPrefix(prefix) {
                let path = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if looksLikeFilePath(path) {
                    return path
                }
            }
        }

        return nil
    }

    // MARK: - Change Type Inference

    /// Infer whether a file is being created, modified, or deleted from context.
    private static func inferChangeType(contextLines: [String], filePath: String?) -> FileChangeType {
        let context = contextLines.joined(separator: " ").lowercased()

        if context.contains("create") || context.contains("new file") || context.contains("add new") {
            return .create
        }
        if context.contains("delete") || context.contains("remove file") {
            return .delete
        }
        if context.contains("modify") || context.contains("update") || context.contains("change") {
            return .modify
        }

        // Default: if file path exists, it's a modify; otherwise treat as create
        return .modify
    }

    // MARK: - Helpers

    /// Does this string look like a file path?
    private static func looksLikeFilePath(_ str: String) -> Bool {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains(" ") || trimmed.hasPrefix("\"") else { return false }
        // Must contain a dot (extension) or a slash (directory)
        return (trimmed.contains(".") || trimmed.contains("/"))
            && !trimmed.hasPrefix("http")
            && !trimmed.hasPrefix("www.")
    }

    /// Is this string a common programming language name?
    private static func isLanguageName(_ str: String) -> Bool {
        let languages: Set<String> = [
            "swift", "python", "javascript", "typescript", "java", "kotlin",
            "go", "rust", "c", "cpp", "csharp", "ruby", "php", "html", "css",
            "sql", "shell", "bash", "zsh", "fish", "yaml", "yml", "json",
            "xml", "toml", "markdown", "md", "text", "txt", "diff", "patch",
            "dockerfile", "makefile", "cmake", "gradle", "groovy", "scala",
            "haskell", "erlang", "elixir", "lua", "perl", "r", "matlab",
            "objc", "objective-c"
        ]
        return languages.contains(str.lowercased())
    }

    /// Map file extension to language name.
    private static func languageFromExtension(_ ext: String) -> String {
        let map: [String: String] = [
            "swift": "swift", "py": "python", "js": "javascript",
            "ts": "typescript", "jsx": "javascript", "tsx": "typescript",
            "java": "java", "kt": "kotlin", "go": "go", "rs": "rust",
            "c": "c", "cpp": "cpp", "h": "c", "hpp": "cpp",
            "cs": "csharp", "rb": "ruby", "php": "php",
            "html": "html", "css": "css", "sql": "sql",
            "sh": "bash", "yml": "yaml", "yaml": "yaml",
            "json": "json", "xml": "xml", "toml": "toml", "md": "markdown"
        ]
        return map[ext.lowercased()] ?? ext
    }
}
