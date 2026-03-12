# DevFlow

DevFlow is a native macOS app that takes you from a Jira ticket to a merged pull request without leaving a single window. It combines ticket discovery, AI-assisted chat (Plan / Implement / Review), local git operations, and GitHub PR creation into one guided workflow.

> **Platform:** macOS 14 Sonoma or later
> **Stack:** Swift 6 · SwiftUI · SwiftData · No external dependencies

---

## Features

- **Ticket discovery:** Fetch, filter, and search assigned Jira tickets
- **AI chat workflows:** Plan, implement, review, and general chat sessions for each ticket
- **Streaming responses:** AI replies stream in real time via a Copilot-compatible gateway
- **Change set pipeline:** Inspect, edit, apply, and commit AI-suggested file changes directly
- **PR creation:** Configure PR details, push, and open PR on GitHub in one step
- **Jira integration:** Auto-transition ticket status and post PR link after creation
- **Session persistence:** All chats and changes are saved across restarts
- **Onboarding wizard:** Guided setup with live integration testing
- **Secure credentials:** All tokens stored securely in macOS Keychain; never written to disk

For architecture and vision details: [doc/details.md](doc/details.md).

---

## For Users — Download and Install

No developer tools required. DevFlow ships as a pre-built `.dmg` for macOS.

### Requirements
- macOS 14 Sonoma or later

### Steps
1. Go to the [Releases page](../../releases) and download the latest `DevFlow.dmg`.
2. Open the `.dmg`, drag **DevFlow.app** to `/Applications`.
3. Right-click (or Control-click) DevFlow.app and choose **Open** on the first launch if Gatekeeper prompts.
4. Complete the setup wizard:
   - Jira: instance URL, email, API token
   - GitHub: host, org, Personal Access Token
   - Copilot: sign in or gateway URL
   - Workspace path: git repositories folder

See [doc/getting-started-users.md](doc/getting-started-users.md) for a walkthrough.

---

## For Developers — Run Locally

DevFlow uses only Apple frameworks. No external package managers. Xcode only.

### Requirements
- macOS 14 Sonoma+
- Xcode 15 or later ([Mac App Store](https://apps.apple.com/app/xcode/id497799835))
- Git (included with Xcode Command Line Tools)

To install Git if missing:
```sh
xcode-select --install
```

### Clone and run
```sh
# 1. Clone the repo
 git clone <repo-url>
 cd DevFlow

# 2. Open in Xcode
 open DevFlow.xcodeproj

# 3. Select DevFlow scheme, "My Mac" destination
# 4. Press ⌘R to build and run
```

### Run tests
```sh
# In Xcode: ⌘U
# From terminal:
swift test
```

### Project layout
```
DevFlow/
 ├── Sources/DevFlow/
 │   ├── App/          # AppState, entry point
 │   ├── Models/       # Jira, GitHub, chat, git
 │   ├── Services/     # JiraService, GitHubService, CopilotService, GitClient
 │   ├── Utilities/    # RetryHelper, CodeBlockParser
 │   └── Views/        # SwiftUI presentation layer
 ├── Tests/DevFlowTests/
 ├── doc/              # Architecture, guides, roadmap
 ├── Package.swift
 └── DevFlow.xcodeproj
```

Further developer setup details: [doc/getting-started-developers.md](doc/getting-started-developers.md).

---

## Roadmap

DevFlow's roadmap is organized by feature phases, not tables.

### Stabilize (Phase A)
- Enhanced integration status visibility
- Improved onboarding validation
- Auto branch creation for commit flows
- Expanded test coverage
- Retry UX improvements

### Quality Gates (Phase B)
- AI-powered test generation
- Commit quality gates and risk scoring
- Static analysis summary
- Review hints in diff views

### Team Adoption (Phase C)
- Shared prompt/playbook library
- Reviewer automation
- Workflow analytics
- Team dashboard
- Jira/PR state synchronization
- Admin controls and environment profiles
- Exportable workflow timelines

### Distribution & Operations (Phase D)
- GitHub Actions release pipeline
- Code signing and notarization
- Auto-update mechanism
- CI test runner on PRs
- Compatibility matrix
- Multi-repository workspace support

More detail: [doc/ROADMAP.md](doc/ROADMAP.md).

---

## Documentation

- [doc/details.md](doc/details.md): Architecture, product vision, feature catalogue
- [doc/getting-started-users.md](doc/getting-started-users.md): User setup guide
- [doc/getting-started-developers.md](doc/getting-started-developers.md): Developer guide
- [doc/ROADMAP.md](doc/ROADMAP.md): Feature roadmap

---

## Contributing

Pull requests are welcome. Open an issue first for major changes. See [doc/getting-started-developers.md](doc/getting-started-developers.md) for setup.

## License

MIT License — see [LICENSE](LICENSE) for details.
