# Getting Started — Developers 🛠️

This guide explains how to build, run, test, and package DevFlow locally on macOS.

If you want the product and architecture context first, read [details.md](details.md).

---

## What to expect

DevFlow is a native macOS app built with Apple frameworks only. That keeps setup simple:

- no Homebrew packages required for the app itself
- no external runtime dependencies
- no `.env` file dance
- no web stack to boot before the app launches

You mainly need Xcode, Git, and access to the integrations you want to test.

---

## Prerequisites

- macOS 14 Sonoma or later
- Xcode 15 or later
- Git via Xcode Command Line Tools

If Git is missing:

```sh
xcode-select --install
```

> You do not need an Apple Developer account just to build and run locally. You only need it for signing and distribution work.

---

## Quick start

```sh
git clone <repo-url>
cd <repo-folder>
open DevFlow.xcodeproj
```

Then in Xcode:

1. Select the **DevFlow** scheme
2. Choose **My Mac**
3. Press **⌘R**

---

## Run tests

In Xcode, use **⌘U**.

From the terminal:

```sh
swift test
```

For Xcode's test runner:

```sh
xcodebuild test \
  -scheme DevFlow \
  -destination 'platform=macOS'
```

---

## Project structure

```text
repo-root/
├── Sources/DevFlow/
│   ├── App/
│   ├── Models/
│   ├── Services/
│   ├── Utilities/
│   └── Views/
├── Tests/DevFlowTests/
├── doc/
├── Package.swift
└── DevFlow.xcodeproj
```

### Architecture rule of thumb

- `Models` hold data and workflow state
- `Services` talk to external systems and local integrations
- `Views` stay focused on presentation
- `Utilities` hold reusable helpers

---

## Technical snapshot

- **Swift tools version:** 6.0
- **Minimum macOS target:** 14.0
- **Persistence:** SwiftData
- **Credential storage:** macOS Keychain
- **External dependencies:** none

---

## Local configuration

DevFlow is configured in-app rather than through environment files:

- Jira settings
- GitHub settings
- Copilot settings
- Workspace path

Settings are stored locally, while secrets are kept in Keychain.

That makes local setup straightforward, but it also means realistic testing usually requires real integration credentials.

---

## Building a local release

```sh
# Archive
xcodebuild archive \
  -scheme DevFlow \
  -archivePath build/DevFlow.xcarchive \
  CODE_SIGNING_ALLOWED=NO

# Export unsigned app
xcodebuild -exportArchive \
  -archivePath build/DevFlow.xcarchive \
  -exportPath build/DevFlowApp \
  -exportOptionsPlist ExportOptions.plist

# Package as DMG
hdiutil create \
  -volname DevFlow \
  -srcfolder build/DevFlowApp/DevFlow.app \
  -ov -format UDZO \
  build/DevFlow.dmg
```

The resulting `build/DevFlow.dmg` is suitable for local sharing, with the usual Gatekeeper first-launch caveat for unsigned apps.

---

## Current contributor realities

- The user-facing product story is a **continuous ticket-to-PR flow**, even though the UI exposes focused modes like `Plan`, `Implement`, and `Review`.
- Distribution is still **unsigned/notarization-pending**.
- The current experience is strongest for **single-user local workflows**.

Keeping these realities in mind helps contributor docs and feature work stay honest.

---

## Contributing

- Branch from `main`
- Keep changes focused
- Add or update tests when behavior changes
- Run `swift test` before opening a PR
- Write PR descriptions that explain the user impact clearly

For upcoming priorities, see [ROADMAP.md](ROADMAP.md).
