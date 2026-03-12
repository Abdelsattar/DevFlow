# Getting Started — Developers

This guide covers everything needed to clone, build, run, and test DevFlow locally on a Mac.

For product context and architecture, see [details.md](details.md).

---

## Prerequisites

| Tool | Minimum version | How to get it |
|---|---|---|
| macOS | 14 Sonoma | System update |
| Xcode | 15 | [Mac App Store](https://apps.apple.com/app/xcode/id497799835) or [developer.apple.com](https://developer.apple.com/xcode/) |
| Xcode Command Line Tools | Included with Xcode 15 | `xcode-select --install` |
| Git | Any recent version | Included with Xcode CLT |

**No external package manager is required.** DevFlow has zero SPM, CocoaPods, or Carthage
dependencies. Everything is built using Apple frameworks only (SwiftUI, SwiftData,
URLSession, UserNotifications, Keychain Services).

**No Apple Developer account is required** to build and run the app on your own Mac in
debug mode. An account is only needed to sign and distribute a release build.

---

## Clone and Open

```sh
git clone <repo-url>
cd DevFlow
open DevFlow.xcodeproj
```

In Xcode:

1. Select the **DevFlow** scheme from the scheme picker at the top.
2. Select **My Mac** as the run destination.
3. Press **⌘R** to build and run.

The app will launch and present the setup wizard on first run.

---

## Running Tests

### In Xcode

Press **⌘U** to run the full test suite.

### From the terminal

```sh
swift test
```

Or with Xcode's test runner:

```sh
xcodebuild test \
  -scheme DevFlow \
  -destination 'platform=macOS'
```

### Test structure

| File | What it covers |
|---|---|
| `ChatModelTests.swift` | Chat message and session model logic |
| `JiraServiceTests.swift` | Jira API parsing and request construction |
| `PersistenceTests.swift` | SwiftData persistence and session restoration |
| `Phase3Tests.swift` | Change set and diff pipeline |
| `Phase4Tests.swift` | PR creation flow |
| `Phase5Tests.swift` | End-to-end workflow integration |

---

## Project Structure

```
DevFlow/
├── Sources/DevFlow/
│   ├── App/
│   │   ├── AppState.swift          # Shared observable state, settings, service init
│   │   └── DevFlowApp.swift        # App entry point, SwiftData container setup
│   ├── Models/
│   │   ├── ChatModels.swift        # Chat session and message types
│   │   ├── PersistentChatModels.swift  # SwiftData-backed persistent models
│   │   ├── JiraModels.swift        # Jira ticket, component, transition types
│   │   ├── GitHubModels.swift      # PR and repository types
│   │   ├── FileChangeModels.swift  # Change set and file diff types
│   │   ├── WorkflowState.swift     # Workflow stage enum and state machine
│   │   └── ADFDocument.swift       # Atlassian Document Format parser
│   ├── Services/
│   │   ├── CopilotService.swift    # OpenAI-compatible streaming chat API
│   │   ├── JiraService.swift       # Jira REST API (tickets, transitions, comments)
│   │   ├── GitHubService.swift     # GitHub REST API (PRs, repos)
│   │   ├── ChatManager.swift       # Session lifecycle, streaming, retries
│   │   ├── ChatPersistenceService.swift  # SwiftData read/write for chat sessions
│   │   ├── GitClient.swift         # Local git: apply, commit, push
│   │   ├── KeychainService.swift   # Secure credential storage
│   │   ├── NotificationService.swift    # macOS UserNotifications
│   │   └── PromptBuilder.swift     # Builds structured prompts per workflow type
│   ├── Utilities/
│   │   ├── RetryHelper.swift       # Exponential backoff retry logic
│   │   ├── CodeBlockParser.swift   # Extracts fenced code blocks from AI output
│   │   └── DateFormatting.swift    # Shared date formatters
│   └── Views/
│       ├── ContentView.swift       # Root split-view layout
│       ├── Onboarding/
│       │   └── SetupWizardView.swift
│       ├── TicketList/
│       │   ├── TicketListView.swift
│       │   ├── TicketRowView.swift
│       │   └── TicketFilterBar.swift
│       ├── Workflow/
│       │   ├── TicketDetailView.swift
│       │   ├── DiffPreviewView.swift
│       │   └── PRCreationView.swift
│       ├── Chat/
│       │   ├── ChatView.swift
│       │   └── ChatTabBar.swift
│       └── Settings/
│           ├── SettingsView.swift
│           ├── JiraSettingsView.swift
│           ├── GitHubSettingsView.swift
│           └── CopilotSettingsView.swift
├── Tests/DevFlowTests/
├── doc/                            # Architecture docs, guides, roadmap
├── .github/workflows/              # CI/CD (release pipeline)
├── Package.swift                   # SPM manifest (macOS 14, Swift 6, no external deps)
├── ExportOptions.plist             # Unsigned archive export config for release builds
└── DevFlow.xcodeproj
```

---

## Key Technical Details

| Property | Value |
|---|---|
| Swift tools version | 6.0 |
| Swift language version | 5.0 |
| Minimum macOS target | 14.0 (Sonoma) |
| Bundle identifier | `io.devflow.app` |
| Persistence layer | SwiftData |
| Credential storage | macOS Keychain |
| External dependencies | None |

---

## Local Configuration for Development

When running locally, you need real credentials for the integrations to work. On first run,
the app's setup wizard will prompt you for all of them. Settings are stored in
`UserDefaults`; tokens are stored in Keychain.

You do **not** need to set any environment variables or create any `.env` files.
All configuration is done through the app's Settings UI (accessible via the gear icon or
**⌘,**).

---

## Building a Release Locally

For distributing a build without Xcode (e.g. sharing with a colleague):

```sh
# Archive
xcodebuild archive \
  -scheme DevFlow \
  -archivePath build/DevFlow.xcarchive \
  CODE_SIGNING_ALLOWED=NO

# Export the .app (unsigned)
xcodebuild -exportArchive \
  -archivePath build/DevFlow.xcarchive \
  -exportPath build/DevFlowApp \
  -exportOptionsPlist ExportOptions.plist

# Package as .dmg
hdiutil create \
  -volname DevFlow \
  -srcfolder build/DevFlowApp/DevFlow.app \
  -ov -format UDZO \
  build/DevFlow.dmg
```

The resulting `build/DevFlow.dmg` can be shared directly. Recipients will need to use the
right-click → Open workaround for Gatekeeper (see
[getting-started-users.md](getting-started-users.md)).

> Automated release builds via GitHub Actions are configured in
> `.github/workflows/release.yml`. See [ROADMAP.md](ROADMAP.md) — Phase D for the
> code signing and notarization plan.

---

## Contributing

1. Fork the repository and create a feature branch from `main`.
2. Make your changes, add tests where appropriate.
3. Run `swift test` and confirm all tests pass.
4. Open a pull request with a clear description of the change.

There is no linting or formatting tooling enforced yet — follow the conventions visible in
the existing code (standard Swift style, no force-unwraps in service/model code).
