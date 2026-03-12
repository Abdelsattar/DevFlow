# Getting Started — Users

This guide covers everything a non-developer needs to download, install, and start using DevFlow.

For a technical overview of the app, see [details.md](details.md).

---

## What You Need

- A Mac running **macOS 14 Sonoma or later**
- Access to your organisation's:
  - **Jira** instance (Cloud or Server) with an API token
  - **GitHub** host with a Personal Access Token (PAT)
  - **Copilot gateway** URL (an OpenAI-compatible chat endpoint)
- A local folder on your Mac that contains the git repositories you work on

---

## Step 1 — Download DevFlow

1. Open the [DevFlow Releases page](../../releases) in your browser.
2. Under the latest release, download **DevFlow.dmg**.

---

## Step 2 — Install

1. Open the downloaded `DevFlow.dmg` file.
2. In the window that appears, drag **DevFlow.app** into your **Applications** folder.
3. Eject the disk image (drag it to the Trash or press ⌘E).

---

## Step 3 — First Launch (Gatekeeper)

Because DevFlow is not yet distributed through the Mac App Store or notarized with Apple,
macOS Gatekeeper will block it on first open.

To bypass this:

1. In Finder, navigate to **Applications**.
2. **Right-click** (or Control-click) `DevFlow.app`.
3. Choose **Open** from the context menu.
4. In the dialog that appears, click **Open** again to confirm.

You only need to do this once. From that point on, DevFlow opens normally.

> **Note:** This requirement will be removed in a future release when code signing and
> notarization are in place. See [ROADMAP.md](ROADMAP.md) — Phase D.

---

## Step 4 — Setup Wizard

On first launch, DevFlow guides you through connecting your accounts. You will need:

### Jira

| Field | Where to find it |
|---|---|
| Instance URL | The base URL of your Jira, e.g. `https://yourcompany.atlassian.net` |
| Email | The email address you log into Jira with |
| API token | Generate one at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens) |
| Project keys | The short keys for projects you want to see tickets from, e.g. `PLAT, CORE` |

### GitHub

| Field | Where to find it |
|---|---|
| Host | Your GitHub hostname, e.g. `github.yourcompany.com` |
| Organisation | The GitHub org that owns the repositories |
| Personal Access Token | Generate one in GitHub → Settings → Developer settings → Personal access tokens. Needs `repo` scope. |

### Copilot Gateway

| Field | Where to find it |
|---|---|
| Gateway URL | The URL of your internal OpenAI-compatible endpoint, e.g. `https://copilot-gateway.yourcompany.com` |

Ask your platform or AI tooling team if you are unsure of this URL.

### Workspace Path

The local directory on your Mac that contains your git repositories, e.g. `~/Projects`.
DevFlow uses this as the root when applying and committing code changes.

Use the **Test Connection** button on each step to verify your credentials before proceeding.

---

## Daily Workflow

Once set up, the typical flow is:

1. **Open DevFlow** — your assigned Jira tickets load automatically.
2. **Pick a ticket** — use the search bar or component/status filters to find your work.
3. **Start a workflow** — open the ticket and choose a session type:
   - **Plan** — talk through the approach with the AI before writing any code
   - **Implement** — get code suggestions, review the diff, apply changes to your local repo
   - **Review** — review your changes with AI assistance before creating a PR
   - **General** — free-form chat for anything else
4. **Apply changes** — review the AI-suggested file changes in the diff view, then apply and commit directly from DevFlow.
5. **Create a PR** — configure the PR title, body, and base branch, then let DevFlow push the branch and open the PR on GitHub.
6. DevFlow can also automatically **transition the Jira ticket** status and post the PR link as a comment.

---

## Updating DevFlow

When a new version is released:

1. Download the new `DevFlow.dmg` from the [Releases page](../../releases).
2. Quit DevFlow if it is running.
3. Drag the new `DevFlow.app` to `/Applications`, replacing the existing version.

> Auto-update support is planned for a future release. See [ROADMAP.md](ROADMAP.md) — Phase D.

---

## Troubleshooting

**Tickets are not loading**
- Check your Jira URL, email, and API token in **Settings → Jira**.
- Make sure the project keys you entered match exactly (case-sensitive).

**AI chat is not responding**
- Verify the Copilot gateway URL in **Settings → Copilot**.
- Check that you have network access to the gateway endpoint.

**PR creation fails**
- Confirm your GitHub PAT is valid and has `repo` scope.
- Make sure the organisation and host are correct in **Settings → GitHub**.

**"Cannot open" on first launch**
- Follow the right-click → Open flow described in Step 3 above.

---

## Credentials and Security

All tokens (Jira API token, GitHub PAT) are stored in your **macOS Keychain** and are
never written to disk in plain text. DevFlow does not transmit your credentials anywhere
other than the configured endpoints.
