# DevFlow

DevFlow is a native macOS app that takes you from a Jira ticket to a merged pull request
without leaving a single window. It combines ticket discovery, AI-assisted chat (Plan /
Implement / Review), local git operations, and GitHub PR creation into one
guided workflow.

> **Platform:** macOS 14 Sonoma or later
> **Stack:** Swift 6 · SwiftUI · SwiftData · No external dependencies

---

## Features

| Area | What it does |
|---|---|
| **Ticket discovery** | Fetches your assigned, non-Done Jira tickets with search and component/status filtering |
| **AI chat workflows** | Purpose-specific chat sessions per ticket: Plan, Implement, Review, and General |
| **Streaming responses** | AI responses stream in real time via your Copilot-compatible gateway |
| **Change set pipeline** | Inspect, edit, apply, and commit AI-suggested file changes from inside the app |
| **PR creation** | Configure title, body, and base branch — then push and create a PR on GitHub in one step |
| **Jira integration** | Automatically transition ticket status and post the PR link as a comment after creation |
| **Session persistence** | Chat sessions and change sets are saved across restarts via SwiftData |
| **Onboarding wizard** | Guided first-run setup with live connection testing for each integration |
| **Secure credentials** | All tokens stored in macOS Keychain — never written to disk in plain text |

For a deeper look at the architecture and product vision, see [doc/details.md](doc/details.md).

---

## For Users — Download and Install

No developer tools required. DevFlow ships as a pre-built `.dmg` for macOS.

### Requirements

- macOS 14 Sonoma or later

### Steps

1. Go to the [Releases page](../../releases) and download the latest `DevFlow.dmg`.
2. Open the `.dmg` and drag **DevFlow.app** to your `/Applications` folder.
3. On first launch, macOS Gatekeeper may block the app because it is not yet notarized.
   Right-click (or Control-click) `DevFlow.app` and choose **Open**, then confirm.
4. Complete the setup wizard:
   - **Jira** — your instance URL, email, and API token
   - **GitHub** — host (GitHub.com or GitHub Enterprise), organisation, and a Personal Access Token
   - **Copilot** — sign in with GitHub Copilot or provide an OpenAI-compatible gateway URL
   - **Workspace path** — the local folder that contains your git repositories

For a full walkthrough of first-run setup and daily use, see
[doc/getting-started-users.md](doc/getting-started-users.md).

---

## For Developers — Run Locally

DevFlow is built entirely with Apple frameworks. There are no external package managers
(no CocoaPods, no Carthage, no SPM dependencies). Xcode is everything you need.

### Requirements

| Tool | Version | Notes |
|---|---|---|
| macOS | 14 Sonoma+ | Required to run the app |
| Xcode | 15 or later | [Download from the Mac App Store](https://apps.apple.com/app/xcode/id497799835) |
| Git | Any recent version | Included with Xcode Command Line Tools |
| Apple Developer account | Not required | Only needed for distribution / notarization |

If Git is not already installed, run:

```sh
xcode-select --install
```

### Clone and run

```sh
# 1. Clone the repository
git clone <repo-url>
cd DevFlow

# 2. Open in Xcode
open DevFlow.xcodeproj

# 3. Select the DevFlow scheme and "My Mac" as the destination
# 4. Press ⌘R to build and run
```

### Run tests

```sh
# In Xcode: ⌘U
# Or from the terminal:
swift test
```

### Project layout

```
DevFlow/
├── Sources/DevFlow/
│   ├── App/          # AppState, app entry point
│   ├── Models/       # Data models (Jira, GitHub, chat, git)
│   ├── Services/     # JiraService, GitHubService, CopilotService, GitClient, …
│   ├── Utilities/    # RetryHelper, CodeBlockParser, DateFormatting
│   └── Views/        # SwiftUI views (Onboarding, TicketList, Chat, Workflow, Settings)
├── Tests/DevFlowTests/
├── doc/              # Architecture, guides, roadmap
├── Package.swift
└── DevFlow.xcodeproj
```

For full developer setup details, environment variables, and architecture notes, see
[doc/getting-started-developers.md](doc/getting-started-developers.md).

---

## Roadmap

| Phase | Focus | Status |
|---|---|---|
| **A — Stabilize** | Error surfacing, onboarding validation, expanded test coverage, auto branch creation before commit | In progress |
| **B — Quality Gates** | Test generation, change-set risk scoring, static analysis before commit | Planned |
| **C — Team Adoption** | Shared prompt templates, reviewer automation, workflow analytics, admin controls | Planned |
| **D — Distribution & Ops** | GitHub Actions release pipeline, code signing & notarization, auto-update, CI on PRs | Planned |

Full roadmap with per-phase detail: [doc/ROADMAP.md](doc/ROADMAP.md).

---

## Documentation

| Document | Description |
|---|---|
| [doc/details.md](doc/details.md) | Full architecture, product vision, and feature catalogue |
| [doc/getting-started-users.md](doc/getting-started-users.md) | Download, install, and first-run setup guide |
| [doc/getting-started-developers.md](doc/getting-started-developers.md) | Clone, build, test, and contribute |
| [doc/ROADMAP.md](doc/ROADMAP.md) | Phased roadmap and upcoming features |

---

## Contributing

Pull requests are welcome. Please open an issue first for significant changes so the
direction can be discussed. See [doc/getting-started-developers.md](doc/getting-started-developers.md)
for the local build setup.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
