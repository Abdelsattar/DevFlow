# Getting Started — Users

This guide helps you download, install, and start using DevFlow. For a technical overview, see [details.md](details.md).

---

## Requirements
- Mac running **macOS 14 Sonoma or later**
- Jira instance (Cloud or Server) and API token
- GitHub host and Personal Access Token (PAT)
- Copilot gateway URL (OpenAI-compatible chat endpoint)
- Local folder containing your git repositories

---

## Installation Steps

### 1. Download DevFlow
- Visit the [Releases page](../../releases) and download the latest `.dmg`.

### 2. Install
- Open the downloaded `.dmg`.
- Drag **DevFlow.app** to your **Applications** folder.

### 3. First Launch (Gatekeeper)
- Right-click (or Control-click) **DevFlow.app** in Applications.
- Choose **Open** and confirm.

> This only needs to be done once; future versions will remove this need when code signing/notarization is added (see [ROADMAP.md](ROADMAP.md) — Phase D).

---

## Setup Wizard
On first launch, DevFlow guides you to connect your integrations:
- **Jira:** instance URL, email, API token, project keys
- **GitHub:** host, organization, PAT
- **Copilot:** gateway URL
- **Workspace path:** local directory for git repositories

Use **Test Connection** at each step to verify credentials.

---

## Daily Workflow

1. Open DevFlow: assigned Jira tickets auto-load.
2. Pick a ticket: search/filter by component/status.
3. Start a workflow session:
   - Plan: AI-assisted discussion
   - Implement: get code suggestions, review/apply changes
   - Review: review changes before PR
   - General: free-form chat
4. Apply changes, commit directly in DevFlow.
5. Create PR: configure details, push branch, open PR on GitHub.
6. DevFlow can auto-transition Jira ticket status and post PR link.

---

## Updating DevFlow

- Download the new `.dmg` from the [Releases page](../../releases).
- Quit DevFlow.
- Replace old version in **Applications**.

> Auto-update is planned in the roadmap (see [ROADMAP.md](ROADMAP.md) — Phase D).

---

## Credentials & Security

- Tokens (Jira, GitHub) are stored in **macOS Keychain**. Never written to disk in plain text.
- Credentials transmitted only to configured endpoints.

---

## Troubleshooting

- **Tickets not loading:** Verify Jira URL/email/token/project keys in Settings → Jira.
- **AI chat not responding:** Check Copilot gateway URL and network access.
- **PR creation fails:** Confirm PAT, organization/host in Settings → GitHub.
- **"Cannot open" app:** Follow right-click → Open instructions above.

---