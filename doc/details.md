# DevFlow App Details

> Quick links:
> [README](../README.md) · [User guide](getting-started-users.md) · [Developer guide](getting-started-developers.md) · [Roadmap](ROADMAP.md)

## 1. What DevFlow Is

DevFlow is a macOS SwiftUI app that helps engineers move from Jira tickets to code changes and pull requests, supported by AI-assisted workflows.

It combines:
- Ticket discovery from Jira
- Multi-session AI chat for planning, implementation, and review
- Local git operations
- Pull request creation on GitHub
- Optional Jira updates after PR creation

The app is built to enable a full "ticket → plan → implement → review → PR" flow inside a single interface.

---

## 2. Product Vision

DevFlow centralizes Jira, editor, terminal, and GitHub steps in a single desktop tool. Its aim is:
- Fast ticket triage
- Structured AI-powered workflows by session type
- Controlled code change and commit flow
- Guided PR creation linkage
- Persisted session and change history for continuity

---

## 3. User Flow

1. Complete onboarding (Jira details, project keys, GitHub PAT, Copilot gateway, workspace path).
2. Ticket list loads with filter/search for assigned work.
3. Start a workflow session (plan, implement, review, general chat).
4. AI guidance and code change suggestions available; user inspects, applies, and commits changes.
5. PR creation: configure, push, create PR, auto-update Jira.

---

## 4. Architecture

- **App Layer:** SwiftUI application with AppState as observable state
- **State & Persistence:**
  - AppState: persistent settings, runtime state, service singletons
  - SwiftData: chat and change set persistence, session restoration
- **Service Layer:** JiraService, GitHubService, CopilotService, ChatManager, GitClient, NotificationService
- **UI Layer:** Onboarding, ticket list, workflow sessions, diff review, PR creation, settings

---

## 5. Current Capabilities

- Guided onboarding and live connection testing
- Jira ticket ingestion, ticket search, and filtering
- Ticket detail rendering
- Multiple chat sessions per ticket
- Streaming AI responses through Copilot
- Persistent chat and change sets across restarts
- Commit-readiness and guided PR creation
- Jira status transition and comment after PR creation

---

## 6. Target Direction

DevFlow’s goal is to become a reliable ticket delivery assistant with strong control, traceability, and consistency for individuals and teams:
- Shorten cycle from ticket to reviewed PR
- Improve code quality with structured AI workflows
- Developer remains in control of applied/committed changes
- Clear automation/logging/status/error reporting
- Support self-hosted, secure authentication
- Scale up for teams with customizable workflows

---

## 7. Feature Roadmap (Phased)

### Phase A — Stabilize
- Enhanced ticket list and integration status visibility
- Improved onboarding validation
- Auto branch creation before commit
- Expanded test coverage for session, chat, and PR flows
- Retry UX improvements

### Phase B — Quality Gates
- AI-powered test generation suggestions
- Quality gates for commit flows
- Change-set risk scoring
- Static analysis summary surfaced in diff review
- Automated review hints

### Phase C — Team Adoption
- Shared prompt/playbook library for teams
- Reviewer automation
- Workflow analytics (delivery time, bottlenecks)
- Team dashboard for workflow progress
- Two-way Jira/PR state sync
- Admin controls and environment profiles
- Exportable audit timeline per ticket

### Phase D — Distribution & Operations
- GitHub Actions release pipeline
- Code signing and notarization
- Auto-update mechanism
- CI test runner integration
- Multi-repository workspace support
- Compatibility matrix for macOS versions

### Ideas Backlog
- Acceptance criteria extraction from tickets
- Implementation checklist generation
- "Definition of done" validator
- Smart workflow next-step recommendations
- Commit message linting, PR template injection
- Duplicate PR detection, branch conflict warnings
- Configurable workflow transitions, SLA indicators
- Bulk ticket operations
- Session handoff notes, offline mode support
- Secret rotation reminders, credential redaction
- Policy guardrails/compliance profiles
- Plug-in integrations (GitLab, Azure DevOps, Linear)
- CLI companion, universal interface

---

## 8. Metrics (Candidate)
- Median time from ticket selection to PR
- PR rework rate
- Workflow completion rate
- Pipeline failures per workflow batch
- User retention and onboarding success

---

## 9. Summary

DevFlow delivers an AI-assisted engineering workflow on macOS. The roadmap aims to further reliability, quality, and team-scale capability for daily delivery.