# DevFlow Roadmap

This roadmap presents phased feature development for DevFlow. For product vision and architecture, see [details.md](details.md).

---

## Phase A — Stabilize

**Goal:** Make the workflow reliable and predictable for daily use.

**Key Features:**
- Enhanced visibility for ticket list and integration status
- Improved onboarding validation and connection workflows
- Automated branch creation before commit
- Expanded test coverage: chat session persistence and PR flow
- Retry UX improvements: clear feedback and user guidance

---

## Phase B — Quality Gates

**Goal:** Raise the quality bar on code changes before they leave the developer's machine.

**Key Features:**
- AI-powered test generation suggestions
- Quality gates before commit: test presence requirements
- Change-set risk scoring: risk labels based on change metadata
- Static analysis summary: lint results surfaced before commit
- Automated review hints integrated into diff review flows

---

## Phase C — Team Adoption

**Goal:** Evolve DevFlow into a platform for team-wide delivery.

**Key Features:**
- Shared prompt and playbook library for reusable team templates
- Reviewer automation based on ownership rules
- Workflow analytics: time tracking and bottleneck insights
- Team dashboard: visibility into workflow progress across members
- Two-way Jira/PR state synchronization
- Admin-level controls: enforce organization settings
- Environment profiles: staged and production config switching
- Exportable workflow timeline: audit trails per ticket

---

## Phase D — Distribution and Operations

**Goal:** Support distribution without Xcode and reliable operation at scale.

**Key Features:**
- GitHub Actions release pipeline: automated builds and releases
- Code signing and notarization for secure deployment
- Auto-update mechanism for seamless upgrades
- CI test runner integrated with PRs
- Compatibility matrix: clear documentation of supported macOS versions
- Multi-repository workspace support

---

## Ideas Backlog

**Potential Future Features:**
- Acceptance criteria extraction from tickets
- Automatic implementation checklist generation
- "Definition of done" validator before PR creation
- Smart workflow recommendations
- Commit message linting and conventional commit support
- Draft PR and template injection
- Duplicate PR detection and conflict warnings
- Configurable workflow transitions and SLA indicators
- Bulk ticket operations
- Session handoff notes for collaboration
- Offline-friendly cached ticket mode
- Secret rotation reminders and fine-grained redaction
- Policy guardrails and compliance profiles
- Plug-in integrations (GitLab, Azure DevOps, Linear)
- Optional CLI companion and universal macOS/iPadOS interface
