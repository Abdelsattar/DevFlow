# Contributing to DevFlow

Thank you for your interest in contributing to DevFlow! This guide will help you get started.

## Quick Start

1. **Fork & clone** the repository
2. Open `DevFlow.xcodeproj` in Xcode 15+
3. Build & run targeting macOS 14+
4. Make your changes, test, and open a PR

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later (Swift 6)
- No external dependencies required

## Project Structure

```
Sources/DevFlow/
├── App/          # Entry point and shared app state
├── Models/       # Data models and workflow state
├── Services/     # Jira, GitHub, Copilot, git, Keychain integrations
├── Utilities/    # Reusable stateless helpers
└── Views/        # SwiftUI presentation layer
```

**Architecture rules:**
- No networking logic in `Views/`
- No UI code in `Services/`
- Keep `Models/` framework-light and deterministic
- Use dependency injection through initializers

## Development Workflow

### 1. Pick an issue

- Check [open issues](https://github.com/Abdelsattar/DevFlow/issues) for `good first issue` or `help wanted` labels.
- Comment on the issue to let others know you're working on it.
- If your idea doesn't have an issue yet, open one first to discuss scope.

### 2. Create a branch

```bash
git checkout -b feat/your-feature-name   # features
git checkout -b fix/your-bug-fix         # bug fixes
git checkout -b docs/your-doc-update     # documentation
```

### 3. Make your changes

- Follow the coding standards below.
- Keep changes small and focused — one concern per PR.
- Update documentation in `doc/` if your change affects behavior.

### 4. Test

```bash
# Run unit tests via Swift
swift test

# Run via Xcode (if touching UI or Xcode-specific behavior)
xcodebuild test -scheme DevFlow -destination 'platform=macOS'
```

### 5. Commit & push

- Write clear, descriptive commit messages.
- Use [Conventional Commits](https://www.conventionalcommits.org/) style: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

### 6. Open a Pull Request

- Fill out the PR template.
- Link the related issue.
- Wait for review — maintainers aim to respond within a few days.

## Coding Standards

### Swift

- Follow the existing style in nearby files.
- Avoid force unwraps (`!`) in service and model code.
- Use `guard` for early exits and clear failure paths.
- Keep functions short and single-purpose.
- Add comments only when intent is non-obvious.
- Reuse existing utilities before adding new helpers.

### SwiftUI

- Keep views declarative; move logic to view model/state/service layers.
- Maintain macOS usability expectations (keyboard shortcuts, split-view behavior).
- Preserve current navigation and workflow stages unless your task explicitly changes them.

### Security

- **Never** log tokens, API keys, or authorization headers.
- Keep credentials in Keychain-backed flows — no plaintext secret storage.
- Redact sensitive values in error messages and diagnostics.
- Use `os.Logger` instead of `print()` for any logging.

### Testing

Focus areas:
- Model transformations and state transitions
- Service parsing and validation paths
- Persistence behavior and restoration
- Workflow regressions across Plan / Implement / Review flows

## What We're Looking For

Check the [Roadmap](doc/ROADMAP.md) for current priorities:

| Phase | Focus |
|-------|-------|
| 🟢 **Current** | Core Jira-to-PR flow, chat modes, suggested changes, commit/PR creation |
| 🟡 **Next** | PR readiness signals, test planning, review context, autonomous improvements |
| 🔵 **Later** | Shared prompts, reviewer automation, team dashboards, multi-repo support |
| ✨ **Exploring** | Acceptance criteria extraction, GitLab/Azure DevOps, draft PR templates |

## What We Won't Merge

- Unrelated refactors bundled into a feature PR
- Broad formatting-only changes
- New external dependencies (unless explicitly discussed and approved)
- Changes that break existing tests without justification
- Code that logs or exposes secrets

## Reporting Bugs & Requesting Features

Use the [issue templates](https://github.com/Abdelsattar/DevFlow/issues/new/choose) — they help us triage faster.

## Code of Conduct

Be respectful, constructive, and inclusive. We're building something useful together.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
