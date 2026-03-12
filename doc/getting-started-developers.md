# Getting Started — Developers

This guide explains how to clone, build, run, and test DevFlow locally on a Mac. For architecture details, see [details.md](details.md).

---

## Prerequisites
- macOS 14 Sonoma or later
- Xcode 15+
- Git (included with Xcode Command Line Tools)

> No external package managers are needed. DevFlow uses Apple frameworks (SwiftUI, SwiftData, URLSession, UserNotifications, Keychain Services).

> You do not need an Apple Developer account to build/run. Only needed for signing and distribution.

---

## Clone and Run

```sh
# Clone the repo
git clone <repo-url>
cd DevFlow

# Open the project in Xcode
open DevFlow.xcodeproj

# Select DevFlow scheme, "My Mac" destination
# Press ⌘R to build and run
```

---

## Running Tests

- In Xcode: ⌘U
- In terminal:
  ```sh
  swift test
  ```
- With Xcode's test runner:
  ```sh
  xcodebuild test \
    -scheme DevFlow \
    -destination 'platform=macOS'
  ```

---

## Project Structure
```
DevFlow/
 ├── Sources/DevFlow/
 │   ├── App/
 │   ├── Models/
 │   ├── Services/
 │   ├── Utilities/
 │   └── Views/
 ├── Tests/DevFlowTests/
 ├── doc/
 ├── .github/workflows/
 ├── Package.swift
 └── DevFlow.xcodeproj
```

---

## Key Technical Details
- Swift tools version: 6.0
- Swift language version: 5.0
- Minimum macOS target: 14.0 (Sonoma)
- Bundle identifier: `io.devflow.app`
- Persistence: SwiftData
- Credential storage: macOS Keychain
- External dependencies: None

---

## Local Configuration

- Setup wizard prompts for real credentials (Jira, GitHub, Copilot, workspace path)
- All settings stored via macOS `UserDefaults`; tokens stored securely in Keychain.
- No environment variables or `.env` files needed; configuration is managed in-app (**⌘,** or gear icon).

---

## Building a Release Locally

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

Resulting `build/DevFlow.dmg` can be shared directly. Recipients will need to right-click → Open for Gatekeeper (see [getting-started-users.md](getting-started-users.md)).

> Automated builds via GitHub Actions: `.github/workflows/release.yml`. See [ROADMAP.md](ROADMAP.md) for code signing, notarization.

---

## Contributing
- Fork the repo and create a branch from `main`
- Make your changes, add tests
- Run `swift test` and ensure all tests pass
- Open a pull request with a clear description

Follow existing code conventions (standard Swift style, avoid force-unwraps in service/model code).