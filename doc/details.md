# DevFlow App Details

> Quick links:
> [README](../README.md) ·
> [User guide](getting-started-users.md) ·
> [Developer guide](getting-started-developers.md) ·
> [Roadmap](ROADMAP.md)

## 1. What DevFlow Is

DevFlow is a macOS SwiftUI desktop app that helps engineers move from Jira tickets to code changes and pull requests with AI-assisted workflows.

At a high level, it combines:
- Ticket discovery from Jira
- Multi-session AI chat for planning, implementation, and review
- Local git operations
- Pull request creation on GitHub
- Optional Jira status/comment updates after PR creation

The app targets a streamlined "ticket -> plan -> implement -> review -> PR" developer flow inside one interface.

## 2. Current Product Vision

DevFlow aims to reduce context switching between Jira, editors, terminals, and GitHub by centralizing workflow steps in a single desktop tool.

Core outcomes the app is designed to achieve today:
- Faster ticket triage for assigned work
- Guided AI workflows with purpose-specific chat sessions
- Controlled code change application and commit preparation
- One guided path to create and link pull requests
- Better continuity via persisted chat sessions and change history

## 3. Core User Flow

1. User completes onboarding setup:
- Jira URL, email, API token
- Project keys and optional component filters
- GitHub host/org and PAT
- Copilot-compatible gateway URL
- Local workspace path

2. App loads and shows ticket list:
- Fetches assigned non-Done tickets from configured Jira projects
- Supports search and component/status filtering

3. User opens ticket details and starts workflow:
- Plan chat session
- Implement chat session
- Review chat session
- General free-form chat session

4. AI chat produces guidance and optional change sets:
- User can inspect/edit/apply file changes
- User can commit approved changes

5. PR creation flow:
- Configure title/body/base branch
- Push branch to remote
- Create PR via GitHub API
- Optionally transition Jira status and add PR link comment

## 4. Main Architecture

## 4.1 App Layer

- SwiftUI application with `AppState` as shared observable state
- On launch:
- Configures SwiftData persistence for chats and file-change history
- Requests notification permissions
- Sets up settings window and status bar item

## 4.2 State & Persistence

- `AppState` stores:
- Persistent settings in `UserDefaults`
- Runtime ticket/filter/loading/error state
- Service singletons used across views

- SwiftData models persist:
- Chat sessions and messages
- Change sets and file changes
- Session restoration at startup
- Automatic pruning of old sessions

## 4.3 Service Layer

- `JiraService`:
- Authentication with API token (via keychain)
- Ticket search, component fetch, transitions, and comments

- `GitHubService`:
- Authentication with PAT (via keychain)
- User/repository checks and PR creation
- Remote URL parsing and PR body helpers

- `CopilotService`:
- OpenAI-compatible API calls via gateway
- Streaming and non-streaming chat completion support

- `ChatManager`:
- Session lifecycle, active-session switching, cancellation
- Streaming orchestration, retries, persistence scheduling

- `GitClient` (workflow support):
- Local git operations for apply/commit/push pipeline

- `NotificationService`:
- User notifications for key app events

## 4.4 UI Layer

Key areas:
- Onboarding setup wizard
- Ticket list and filters
- Ticket detail and workflow action buttons
- Multi-tab chat interface
- Diff preview and file-change review
- PR creation pipeline view
- Settings pages for Jira, GitHub, and Copilot

## 5. What Is Already Working (Current Capability Snapshot)

- Guided onboarding with connection testing
- Jira ticket ingestion for configured projects
- Ticket filtering and searchable list
- Ticket detail rendering (description/comments/components)
- Multiple chat sessions per ticket by workflow purpose
- Streaming AI responses through Copilot gateway
- Chat session persistence across restarts
- Change set handling and commit-readiness state
- Guided PR creation flow with progress/status states
- Jira integration after PR creation (transition + comment)

## 6. What We Want to Achieve (Target Product Direction)

DevFlow should become a reliable end-to-end engineering assistant for ticket delivery, with strong control, traceability, and team-level consistency.

Primary goals:
- Shorten cycle time from assigned ticket to reviewed PR
- Improve implementation quality via structured AI workflows
- Keep developers in control of every applied/committed change
- Make automation observable (clear logs, statuses, error handling)
- Support enterprise constraints (self-hosted services, secure auth)
- Scale from individual usage to team-wide adoption

## 7. Potential Features to Add

## 7.1 Workflow Intelligence

- Acceptance criteria extraction from ticket description/comments
- Automatic implementation checklist generation per ticket
- "Definition of done" validator before PR creation
- Smart next-step recommendations based on workflow stage

## 7.2 Code Change Quality

- Test impact suggestions based on changed files
- Auto-generated unit/integration test stubs
- Risk scoring for each change set (high/medium/low)
- Static analysis summary before commit

## 7.3 Git & PR Enhancements

- Auto branch naming templates from ticket metadata
- Commit message linting/conventional commit support
- Draft PR mode and PR template injection
- Auto-request reviewers by CODEOWNERS/path ownership
- Duplicate PR detection and branch conflict warnings

## 7.4 Jira Automation

- Configurable workflow mappings per project
- Two-way sync of ticket state and PR state
- SLA/watcher signals and "needs attention" indicators
- Bulk operations for multiple tickets

## 7.5 Collaboration & Visibility

- Team dashboard for ticket progress across stages
- Shared prompt/playbook library per team
- Exportable workflow timeline (audit trail)
- Session handoff notes for pair programming or reviewer context

## 7.6 Reliability & Operations

- Offline-friendly cached ticket mode
- Retry queues for failed network actions
- Structured diagnostics view (requests, failures, latency)
- Improved telemetry and anonymized usage metrics

## 7.7 Security & Compliance

- Secret rotation reminders for tokens
- Fine-grained redaction of sensitive ticket/code content
- Policy guardrails for unsafe or prohibited code changes
- Organization-level settings lock and compliance profiles

## 7.8 Platform Expansion

- Multi-repository workspace support in one ticket workflow
- Plug-in style integrations (GitLab, Azure DevOps, Linear)
- Optional CLI companion for terminal-first users
- Future iPad/macOS universal interface considerations

## 8. Suggested Near-Term Roadmap

Phase A (stabilize):
- Improve error surfacing and retry UX across integrations
- Add stronger validation during onboarding and settings edits
- Expand test coverage for chat persistence and PR flow edge cases

Phase B (quality):
- Add test generation and quality gates before commit/PR
- Introduce change-set risk scoring and review hints

Phase C (team adoption):
- Shared templates, reviewer automation, and workflow analytics
- Admin-level controls and environment profiles

## 9. Success Metrics

Candidate metrics to track progress:
- Median time from ticket selection to PR creation
- PR rework rate after review
- % of tickets completed using full DevFlow workflow
- Number of failed pipeline steps per 100 workflows
- User retention (weekly active users)
- Setup success rate during onboarding

## 10. Summary

DevFlow already provides a strong foundation for an AI-assisted engineering delivery workflow on macOS. The next step is to harden reliability, strengthen quality controls, and add team-scale capabilities so it becomes a dependable day-to-day delivery platform, not just a helpful assistant.