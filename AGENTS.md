# AGENTS.md

Guidance for coding agents working in this repository.

## Project Snapshot

- App: DevFlow (native macOS app)
- Language: Swift
- UI: SwiftUI
- Persistence: SwiftData
- Target platform: macOS 14+
- Build system: Xcode project + Swift Package manifest
- Dependencies: No external packages

## Primary Goals

- Keep behavior stable while making minimal, focused changes.
- Preserve existing architecture boundaries.
- Prefer safe, testable code over clever shortcuts.
- Keep user secrets and tokens protected.

## Architecture Boundaries

- `Sources/DevFlow/App`: app entry point and shared app state wiring.
- `Sources/DevFlow/Models`: pure data models and workflow state definitions.
- `Sources/DevFlow/Services`: integration logic (Jira, GitHub, Copilot, git, Keychain, notifications).
- `Sources/DevFlow/Utilities`: reusable stateless helpers.
- `Sources/DevFlow/Views`: SwiftUI presentation layer only.

Rules:
- Do not put networking logic in `Views`.
- Do not put UI code in `Services`.
- Keep `Models` framework-light and deterministic when possible.
- Prefer dependency injection through initializers for service collaboration.

## Swift Coding Standards

- Follow existing style in nearby files and keep diffs small.
- Avoid force unwraps (`!`) in service and model code.
- Use `guard` for early exits and clear failure paths.
- Keep functions short and single-purpose.
- Add comments only when intent is non-obvious.
- Reuse existing utilities before adding new helpers.

## SwiftUI Standards

- Keep views declarative and side effects explicit.
- Avoid heavy business logic in `body`; move logic to view model/state/service layers.
- Preserve current navigation and workflow stages unless the task explicitly changes them.
- Maintain macOS usability expectations (keyboard shortcuts, split-view behavior, settings flow).

## Security and Secrets

- Never log tokens, API keys, or authorization headers.
- Keep credentials in Keychain-backed flows.
- Do not introduce plaintext secret storage.
- Redact sensitive values in error messages and diagnostics.

## Networking and Integrations

- Reuse existing services:
  - `JiraService`
  - `GitHubService`
  - `CopilotService`
  - `GitClient`
- Keep request/response parsing close to service boundaries.
- Prefer typed models over ad-hoc dictionaries.
- Handle transient failures with retry/backoff patterns already used in the codebase.

## Testing Expectations

When changing behavior, add or update tests under `Tests/DevFlowTests`.

Focus areas:
- Model transformations and state transitions.
- Service parsing/validation paths.
- Persistence behavior and restoration.
- Workflow regressions across Plan/Implement/Review flows.

## Validation Checklist

Before finishing substantial changes, run what is applicable:

```sh
swift test
```

If Xcode-specific behavior is touched, also validate with:

```sh
xcodebuild test -scheme DevFlow -destination 'platform=macOS'
```

## Change Management

- Prefer incremental edits over large rewrites.
- Do not rename/move files unless required by the task.
- Avoid introducing new dependencies unless explicitly requested.
- Keep public types and interfaces stable unless a change is required.
- Document non-trivial decisions in `doc/` when they affect future contributors.

## File and Docs Conventions

- Keep developer-facing docs in `doc/`.
- Keep user-facing setup and run guidance aligned with `README.md`.
- If behavior changes, update related docs in the same change.

## Agent Workflow

1. Read relevant files first; do not guess.
2. Propose or apply the smallest viable change.
3. Validate with tests/checks where feasible.
4. Summarize:
   - what changed,
   - why it changed,
   - how it was validated,
   - any follow-up work.

## Non-Goals

- Do not add unrelated refactors during focused fixes.
- Do not add broad formatting-only edits.
- Do not alter release/signing behavior unless explicitly requested.
