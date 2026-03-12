import Testing
@testable import DevFlow

// MARK: - CodeBlockParser Tests

@Suite("CodeBlockParser Tests")
struct CodeBlockParserTests {

    // MARK: - Format 1: File path on line before code block

    @Test("Extracts file change with bold backtick path before fence")
    func format1BoldBacktickPath() {
        let markdown = """
        Here is the implementation:

        **`src/Models/User.swift`**
        ```swift
        struct User {
            let id: String
            let name: String
        }
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].filePath == "src/Models/User.swift")
        #expect(changes[0].language == "swift")
        #expect(changes[0].content.contains("struct User"))
    }

    @Test("Extracts file change with bold path before fence")
    func format1BoldPath() {
        let markdown = """
        **src/Config.swift**
        ```swift
        let config = "default"
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].filePath == "src/Config.swift")
    }

    // MARK: - Format 2: File path in fence info string

    @Test("Extracts file change with path in fence info string")
    func format2FenceInfoPath() {
        let markdown = """
        ```swift:Sources/App/main.swift
        import Foundation
        print("Hello")
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].filePath == "Sources/App/main.swift")
        #expect(changes[0].language == "swift")
        #expect(changes[0].content.contains("print(\"Hello\")"))
    }

    // MARK: - Format 3: File path comment inside code block

    @Test("Extracts file change with file path comment inside code block")
    func format3FilePathComment() {
        let markdown = """
        ```swift
        // File: Sources/Models/Item.swift
        struct Item {
            let id: Int
        }
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].filePath == "Sources/Models/Item.swift")
        // The file path comment should be stripped from content
        #expect(!changes[0].content.contains("// File:"))
        #expect(changes[0].content.contains("struct Item"))
    }

    // MARK: - Multiple Code Blocks

    @Test("Extracts multiple file changes from markdown")
    func multipleCodeBlocks() {
        let markdown = """
        I'll create two files:

        **`Sources/Models/Config.swift`** (new file)
        ```swift
        struct Config {
            let apiURL: String
        }
        ```

        **`Sources/Services/APIClient.swift`** (modify)
        ```swift
        class APIClient {
            let config: Config
        }
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 2)
        guard changes.count == 2 else { return }
        #expect(changes[0].filePath == "Sources/Models/Config.swift")
        #expect(changes[1].filePath == "Sources/Services/APIClient.swift")
    }

    // MARK: - Change Type Inference

    @Test("Infers create change type from context")
    func inferCreateType() {
        let markdown = """
        Create new file:

        **`src/NewFile.swift`**
        ```swift
        // new content
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].changeType == .create)
    }

    @Test("Infers modify change type from context")
    func inferModifyType() {
        let markdown = """
        Update the existing file:

        **`src/Existing.swift`**
        ```swift
        // updated content
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].changeType == .modify)
    }

    @Test("Infers delete change type from context")
    func inferDeleteType() {
        let markdown = """
        Delete this file:

        **`src/OldFile.swift`**
        ```swift
        // to be removed
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].changeType == .delete)
    }

    // MARK: - No File Path

    @Test("Skips code blocks without file paths")
    func noFilePath() {
        let markdown = """
        Here's an example:

        ```swift
        let x = 42
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("Handles empty markdown")
    func emptyMarkdown() {
        let changes = CodeBlockParser.extractFileChanges(from: "")
        #expect(changes.isEmpty)
    }

    @Test("Handles markdown without code blocks")
    func noCodeBlocks() {
        let markdown = "Just some text without any code blocks."
        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.isEmpty)
    }

    @Test("Handles heading with file path")
    func headingFilePath() {
        let markdown = """
        ### Sources/Utils/Helper.swift
        ```swift
        func helper() {}
        ```
        """

        let changes = CodeBlockParser.extractFileChanges(from: markdown)
        #expect(changes.count == 1)
        #expect(changes[0].filePath == "Sources/Utils/Helper.swift")
    }

    @Test("ParsedBlock contains correct language")
    func parsedBlockLanguage() {
        let markdown = """
        **`test.py`**
        ```python
        print("hello")
        ```
        """

        let blocks = CodeBlockParser.parseCodeBlocks(from: markdown)
        #expect(blocks.count == 1)
        #expect(blocks[0].language == "python")
    }
}

// MARK: - GitClient Helper Tests

@Suite("GitClient Helper Tests")
struct GitClientHelperTests {

    @Test("Branch name generation follows convention")
    func branchNameGeneration() {
        let branch = GitClient.branchName(
            ticketKey: "PLAT-123",
            summary: "Add user authentication flow"
        )
        #expect(branch == "PLAT-123-add-user-authentication-flow")
    }

    @Test("Branch name handles special characters in summary")
    func branchNameSpecialChars() {
        let branch = GitClient.branchName(
            ticketKey: "PLAT-456",
            summary: "Fix bug: API returns 500 on /users endpoint!"
        )
        #expect(branch.hasPrefix("PLAT-456-"))
        #expect(!branch.contains(" "))
        #expect(!branch.contains(":"))
        #expect(!branch.contains("!"))
    }

    @Test("Branch name truncates long summaries")
    func branchNameTruncation() {
        let longSummary = String(repeating: "a very long description ", count: 10)
        let branch = GitClient.branchName(ticketKey: "PLAT-789", summary: longSummary)
        // The slug portion should be capped at 50 chars
        let slug = branch.replacingOccurrences(of: "PLAT-789-", with: "")
        #expect(slug.count <= 50)
    }

    @Test("Branch name preserves ticket key casing")
    func branchNameCasing() {
        let branch = GitClient.branchName(ticketKey: "PLAT-100", summary: "Test")
        #expect(branch.hasPrefix("PLAT-100-"))
    }

    @Test("Commit message generation")
    func commitMessageGeneration() {
        let message = GitClient.commitMessage(
            ticketKey: "PLAT-123",
            description: "Add user authentication flow"
        )
        #expect(message == "PLAT-123: Add user authentication flow")
    }

    @Test("Commit message preserves ticket key casing")
    func commitMessageCasing() {
        let message = GitClient.commitMessage(
            ticketKey: "PLAT-456",
            description: "Fix login bug"
        )
        #expect(message.hasPrefix("PLAT-456:"))
    }
}

// MARK: - FileChange Model Tests

@Suite("FileChange Model Tests")
struct FileChangeModelTests {

    @Test("FileChange computes fileName and directory")
    func fileChangePathComponents() {
        let change = FileChange(
            filePath: "Sources/Models/User.swift",
            language: "swift",
            content: "struct User {}"
        )
        #expect(change.fileName == "User.swift")
        #expect(change.directory == "Sources/Models")
    }

    @Test("FileChange isPending when not applied or rejected")
    func fileChangePending() {
        let change = FileChange(filePath: "test.swift", content: "code")
        #expect(change.isPending)
        #expect(!change.isApplied)
        #expect(!change.isRejected)
    }

    @Test("FileChange lineCount computation")
    func fileChangeLineCount() {
        let change = FileChange(
            filePath: "test.swift",
            content: "line1\nline2\nline3"
        )
        #expect(change.lineCount == 3)
    }

    @Test("ChangeSet tracks counts correctly")
    func changeSetCounts() {
        let changes = [
            FileChange(filePath: "a.swift", content: "a"),
            FileChange(filePath: "b.swift", content: "b"),
            FileChange(filePath: "c.swift", content: "c", isApplied: true),
            FileChange(filePath: "d.swift", content: "d", isRejected: true),
        ]

        let changeSet = ChangeSet(
            ticketKey: "PLAT-100",
            description: "Test",
            changes: changes
        )

        #expect(changeSet.pendingCount == 2)
        #expect(changeSet.appliedCount == 1)
        #expect(changeSet.rejectedCount == 1)
        #expect(!changeSet.isFullyReviewed)
        #expect(changeSet.hasAppliedChanges)
    }

    @Test("ChangeSet isFullyReviewed when all changes resolved")
    func changeSetFullyReviewed() {
        let changes = [
            FileChange(filePath: "a.swift", content: "a", isApplied: true),
            FileChange(filePath: "b.swift", content: "b", isRejected: true),
        ]

        let changeSet = ChangeSet(
            ticketKey: "PLAT-100",
            description: "Test",
            changes: changes
        )

        #expect(changeSet.isFullyReviewed)
    }

    @Test("FileChangeType display properties")
    func fileChangeTypeProperties() {
        #expect(FileChangeType.create.displayName == "New File")
        #expect(FileChangeType.modify.displayName == "Modified")
        #expect(FileChangeType.delete.displayName == "Deleted")

        #expect(!FileChangeType.create.icon.isEmpty)
        #expect(!FileChangeType.modify.icon.isEmpty)
        #expect(!FileChangeType.delete.icon.isEmpty)
    }
}
