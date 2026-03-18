# DevFlow Details

> Quick links: [README](../README.md) · [User guide](getting-started-users.md) · [Developer guide](getting-started-developers.md) · [Roadmap](ROADMAP.md)

## What DevFlow is

DevFlow is a macOS app for handling the everyday engineering path from **Jira ticket → local code work → ready-to-merge pull request** in one place.

It brings together:

- Jira ticket discovery and context
- AI-assisted conversations for planning, coding, review, or general help
- Local git operations
- Pull request creation on GitHub
- Optional Jira updates after the PR is opened

The key idea is **less tool-hopping** and a more connected delivery flow.

---

## The product promise

DevFlow tries to make software delivery feel flatter and more transparent:

- Open one ticket and keep the full thread of work around it.
- Use AI when useful, not as a hard requirement.
- Keep the developer in charge of what gets applied and committed.
- Preserve context so work survives restarts.
- Reduce the friction between "I understand the task" and "the PR is ready."

### North star ✨

The product goal is to make one thing feel beautifully simple:

**take a Jira ticket and move it all the way to a ready-to-merge PR in one connected flow.**

---

## How the flow works today

1. **Onboarding**
   - Connect Jira
   - Select project scope
   - Connect GitHub
   - Connect Copilot
   - Pick a local workspace path

2. **Ticket selection**
   - Load assigned Jira tickets
   - Search and filter the list
   - Open the ticket you want to work on

3. **Working the ticket**
   - Start a focused `Plan`, `Implement`, `Review`, or `Chat` session
   - Use one mode or several; they are optional work surfaces, not mandatory steps
   - Keep multiple sessions per ticket if that helps your process

4. **Handling changes**
   - Review suggested edits
   - Apply or refine them
   - Commit locally from inside DevFlow

5. **Shipping**
   - Configure the PR
   - Push the branch
   - Open the PR on GitHub
   - Optionally transition the Jira ticket and post the PR link back

6. **Optional autonomy**
   - Autonomous Mode can run a guided end-to-end flow with approval checkpoints

---

## Modes inside one flow

DevFlow does expose visible chat purposes in the UI:

- `Plan`
- `Implement`
- `Review`
- `Chat`

That matters because users really do see those labels in the product. Still, the docs should present them honestly: they are **helpful modes inside one continuous workflow**, not a rigid methodology you must follow every time.

---

## 🟢 Available today

- Guided setup with live connection checks
- Jira ticket loading, filtering, and search
- Ticket detail views
- Persistent AI conversations per ticket
- Streaming responses
- Suggested change extraction and review
- Local commits inside the app
- GitHub pull request creation
- Optional Jira status transition and PR comment
- Session and change-set persistence across restarts
- Autonomous Mode with different approval levels

---

## 🟡 Coming next

- Stronger PR-readiness signals before shipping
- Better AI assistance for implementation and test planning
- Richer review context around code changes
- Smoother PR drafting and handoff
- A tighter end-to-end path from selected ticket to finished PR

---

## Boundaries and transparency

These are worth stating clearly in public docs:

- **Local-first workflow:** DevFlow is strongest when one person is working from a local macOS machine.
- **Single workspace root:** the app currently centers around one configured workspace path.
- **Unsigned distribution today:** first launch may require the usual Gatekeeper override flow.
- **Manual app updates:** there is no built-in auto-update path yet.
- **Live PR creation:** there is no draft-PR flow yet.
- **Autonomous Mode is still best treated as supervised automation:** useful, but not a "hands-off team robot."

---

## Architecture snapshot

- **App layer:** SwiftUI app with shared app state
- **Persistence:** SwiftData for sessions and change history
- **Services:** Jira, GitHub, Copilot, git, notifications, and orchestration logic
- **Views:** onboarding, ticket list, ticket detail, chat sessions, change review, PR creation, and settings

The codebase keeps a clear split between UI, models, services, and utilities. For contributor setup, see [getting-started-developers.md](getting-started-developers.md).

---

## Direction

The roadmap is described as **current / next / later / exploring**.

That is intentional. DevFlow is better communicated through visible product growth: first perfect the core Jira-to-PR flow, then widen what that flow can do.

Read the full roadmap here: [ROADMAP.md](ROADMAP.md)

---

## Useful terms

- **Workflow:** the overall ticket-to-PR journey inside the app
- **Mode:** one of the focused chat purposes such as `Plan`, `Implement`, `Review`, or `Chat`
- **Change set:** a group of code edits suggested during a session and reviewed by the user
- **Autonomous Mode:** an orchestrated run across multiple modes with approval checkpoints
- **Copilot connection:** the AI backend connection, which may be sign-in based or a compatible gateway depending on setup

---

## Summary

DevFlow is not trying to replace engineering judgment. It is trying to make the path from ticket to PR calmer, more connected, and easier to repeat.
