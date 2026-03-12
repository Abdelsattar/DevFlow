# DevFlow Roadmap

This document tracks the phased development plan for DevFlow.
For product vision, architecture, and feature catalogue, see [details.md](details.md).

Status legend: `Done` · `In progress` · `Planned`

---

## Phase A — Stabilize

**Goal:** Make the existing workflow reliable and predictable for daily use.

| Item | Status | Notes |
|---|---|---|
| Error surfacing in ticket list view | In progress | Errors from Jira fetch are captured in AppState but not shown in the UI |
| Error surfacing across all integrations | In progress | GitHub and Copilot errors need visible feedback in their respective views |
| Stronger onboarding validation | In progress | Connection tests exist; edge cases (invalid project keys, wrong org) need better messages |
| Auto branch creation before commit | In progress | Currently commits directly to whatever branch is checked out; should create/checkout the branch from the change set before committing |
| Expanded test coverage — chat persistence | Planned | Cover session restoration, message ordering, pruning edge cases |
| Expanded test coverage — PR flow | Planned | Cover push failures, duplicate PR detection, network retries |
| Retry UX improvements | Planned | Surface retry state and failure counts to the user during streaming and API calls |

---

## Phase B — Quality Gates

**Goal:** Raise the quality bar on code changes before they leave the developer's machine.

| Item | Status | Notes |
|---|---|---|
| Test generation suggestions | Planned | AI suggests test stubs based on changed files |
| Quality gates before commit | Planned | Block commit if no tests exist for changed files (configurable) |
| Change-set risk scoring | Planned | High / medium / low risk label per change set based on file type, diff size, and coverage |
| Static analysis summary | Planned | Run `swiftlint` or similar on staged changes and surface results in the diff view before commit |
| Review hints from diff | Planned | Send the full git diff to the Review chat session automatically, not just the ticket description |

---

## Phase C — Team Adoption

**Goal:** Extend DevFlow from a personal tool to a team-wide delivery platform.

| Item | Status | Notes |
|---|---|---|
| Shared prompt / playbook library | Planned | Teams can publish reusable prompt templates (e.g. "our standard implementation checklist") |
| Reviewer automation | Planned | Auto-request reviewers based on CODEOWNERS or path ownership rules |
| Workflow analytics | Planned | Track time from ticket open to PR created; surface bottlenecks |
| Team dashboard | Planned | View ticket workflow progress across team members |
| Two-way Jira/PR state sync | Planned | Automatically transition ticket when PR is merged |
| Admin-level controls | Planned | Lock settings fields at organisation level (e.g. enforce specific Copilot gateway URL) |
| Environment profiles | Planned | Switch between staging/production Jira and GitHub configs without re-entering credentials |
| Exportable workflow timeline | Planned | Audit trail of AI sessions, applied changes, and PR events per ticket |

---

## Phase D — Distribution and Operations

**Goal:** Make DevFlow distributable without requiring Xcode, and run it reliably at team scale.

| Item | Status | Notes |
|---|---|---|
| GitHub Actions release pipeline | Planned | Automatically build, package as `.dmg`, and publish to GitHub Releases on every `v*.*.*` tag push. Workflow is in `.github/workflows/release.yml`. |
| Code signing | Planned | Sign the `.app` with an Apple Developer ID certificate so macOS does not quarantine it |
| Notarization | Planned | Submit the signed `.dmg` to Apple for notarization so users don't need the right-click → Open workaround |
| Auto-update mechanism | Planned | Integrate [Sparkle](https://sparkle-project.org) so the app can update itself without user intervention |
| CI test runner on PRs | Planned | Run `xcodebuild test` on every pull request via GitHub Actions |
| macOS version compatibility matrix | Planned | Test and document which macOS versions are supported for each release |
| Multi-repository workspace support | Planned | Let a single ticket workflow span more than one local repository |

---

## Ideas Backlog

Items that have been raised but not yet scheduled into a phase.

### Workflow Intelligence
- Acceptance criteria extraction from ticket description/comments
- Automatic implementation checklist generation per ticket
- "Definition of done" validator before PR creation
- Smart next-step recommendations based on workflow stage

### Git and PR Enhancements
- Commit message linting and conventional commit support
- Draft PR mode and PR template injection
- Duplicate PR detection and branch conflict warnings

### Jira Automation
- Configurable workflow transition mappings per project
- SLA and "needs attention" indicators
- Bulk operations across multiple tickets

### Collaboration
- Session handoff notes for pair programming and reviewer context
- Offline-friendly cached ticket mode

### Security and Compliance
- Secret rotation reminders for tokens
- Fine-grained redaction of sensitive ticket content in AI sessions
- Policy guardrails for unsafe or prohibited code patterns
- Organisation-level settings lock and compliance profiles

### Platform Expansion
- Plug-in style integrations for GitLab, Azure DevOps, and Linear
- Optional CLI companion for terminal-first users
- Universal macOS/iPadOS interface
