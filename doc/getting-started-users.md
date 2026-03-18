# Getting Started — Users ✨

This guide helps you install DevFlow, connect your tools, and get through your first ticket smoothly.

For the broader product picture, see [details.md](details.md).

---

## Before you install

You will need:

- A Mac running **macOS 14 Sonoma or later**
- Access to **Jira**
- Access to **GitHub**
- A **Copilot** connection
- A local folder containing the git repositories you work in

Depending on your setup, Copilot may be configured through sign-in or through a compatible gateway URL.

---

## Install DevFlow

1. Open the [Releases page](../../releases).
2. Download the latest `.dmg`.
3. Open the disk image.
4. Drag **DevFlow.app** into **Applications**.

### First launch note

Current builds may require a one-time **right-click → Open** flow because notarized distribution is still ahead on the roadmap.

---

## Connect your tools

When DevFlow launches for the first time, it walks you through setup:

- **Jira** — instance URL, account details, token or auth flow, and project scope
- **GitHub** — host, organization, and personal access token
- **Copilot** — sign-in or compatible gateway configuration
- **Workspace** — the local root folder where your git repositories live

Use the built-in connection tests while setting things up. It is much easier to fix configuration here than after you open a ticket.

---

## Your everyday flow

DevFlow works best when you think of it as one flat workflow:

1. Open DevFlow and load your assigned Jira tickets.
2. Pick a ticket.
3. Start the kind of conversation you need.
4. Review and apply code changes.
5. Commit locally.
6. Create the PR and optionally update Jira.

---

## Pick the mode that helps

The app shows four focused modes:

- **Plan** — discuss approach, scope, edge cases, or acceptance criteria
- **Implement** — generate and refine code changes
- **Review** — sanity-check the result before shipping
- **Chat** — ask anything without a specific lane

You do **not** need to use all four every time. They are there to support your workflow, not to force one.

---

## Autonomous Mode

DevFlow also includes **Autonomous Mode**, which can guide a ticket through a broader end-to-end run with approval checkpoints.

That is the exciting version. The practical version is:

- use it for focused work,
- expect to review important decisions,
- and treat it as supervised automation rather than a fire-and-forget system.

Today, it is best suited to one ticket at a time in one workspace.

---

## Updating DevFlow

Updates are currently manual:

1. Download the latest `.dmg` from the [Releases page](../../releases).
2. Quit DevFlow.
3. Replace the old app in **Applications**.

---

## Security and storage

- Secrets are stored in **macOS Keychain**
- App settings are stored locally on your Mac
- DevFlow does **not** write tokens to plaintext project files

---

## Current limitations

It is better to know these up front:

- DevFlow centers on **one configured workspace root**
- PR creation is **live**, not draft-based
- Signed/notarized distribution is **not** in place yet
- Built-in auto-update is **not** available yet

---

## Troubleshooting

- **Tickets are not loading**  
  Re-check your Jira URL, authentication details, and project scope in Settings.

- **AI chat is not responding**  
  Verify the Copilot connection and confirm your Mac has network access to that endpoint.

- **PR creation fails**  
  Re-check GitHub host, organization, and PAT settings.

- **The app will not open**  
  Use the one-time right-click → **Open** flow from Finder.

---

## Need more context?

- Product overview: [details.md](details.md)
- Developer setup: [getting-started-developers.md](getting-started-developers.md)
- Direction and upcoming improvements: [ROADMAP.md](ROADMAP.md)
