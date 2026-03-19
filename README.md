# DevFlow 🚀

DevFlow is a native macOS app built to turn a **Jira ticket into a ready-to-merge pull request** without juggling five different tools. It keeps ticket context, AI assistance, local git work, and GitHub handoff in one place so the flow feels continuous instead of fragmented.

> **Platform:** macOS 14 Sonoma or later  
> **Stack:** Swift 6 · SwiftUI · SwiftData · no external runtime dependencies

> **🚧 Status:** DevFlow is still under active development. The first beta release is coming soon.  
> **🛠️ Want to try it now?** You can clone this repository, open `DevFlow.xcodeproj`, and run the app locally today.

---

## Why DevFlow

- **One continuous workspace:** ticket context, AI chat, code changes, commits, and PR creation stay in the same app.
- **Flexible assistance:** use focused chat modes like `Plan`, `Implement`, `Review`, or a general `Chat` when they help; skip around as needed.
- **Developer stays in control:** inspect, edit, and approve suggested changes before they become commits.
- **Built for continuity:** chats and change sets persist across restarts.
- **Security-first defaults:** credentials live in macOS Keychain, not in plaintext files.

## 🎯 The goal

DevFlow is not just a chat app and not just a PR helper.

The goal is simple: take a ticket from **Jira → context → code changes → review → ready-to-merge PR** in one clear flow, and keep improving that flow until it feels natural every day.

If you want the deeper product and architecture picture, start with [doc/details.md](doc/details.md).

---

## How the flow works

DevFlow is best understood as one flat ticket-to-PR flow:

1. **Connect your tools**  
   Add Jira, GitHub, Copilot, and a local workspace folder in the setup wizard.

2. **Pick a ticket**  
   Browse or search assigned Jira work, then open the ticket you want to handle.

3. **Choose how much help you want**  
   Start a focused `Plan`, `Implement`, `Review`, or `Chat` session. These are tools, not mandatory steps.

4. **Review and apply code changes**  
   Inspect suggested file edits, adjust them if needed, then commit locally.

5. **Create the PR**  
   Push the branch, open a pull request on GitHub, and optionally update the Jira ticket.

### Optional: Autonomous Mode

DevFlow also includes **Autonomous Mode** for a more guided end-to-end run through planning, implementation, review, and PR creation with approval checkpoints.

It is powerful, but the transparent version is this: treat it as an assisted workflow, not magic. Today it is best for one focused ticket at a time.

---

## 🟢 Available today

- ✅ Guided onboarding with live integration checks
- ✅ Jira ticket discovery, filtering, and search
- ✅ Persistent AI chat sessions per ticket
- ✅ Streaming AI responses
- ✅ Suggested code changes with review/apply/edit flow
- ✅ Local git commits from inside the app
- ✅ Pull request creation on GitHub
- ✅ Optional Jira status updates and PR link posting
- ✅ Session restoration across restarts
- ✅ Autonomous Mode with approval checkpoints

## 🟡 Coming next

- PR-readiness signals that make review decisions faster
- Better AI support around test and implementation planning
- More polished review context before opening the PR
- Drafting and handoff improvements around PR creation
- A stronger end-to-end flow for turning one ticket into one clean delivery path

---

## What to know up front

Good docs should be honest, so here are the main current constraints:

- **Unsigned distribution for now:** first launch may require right-click → **Open** because notarized distribution is still ahead on the roadmap.
- **Manual updates:** install new versions by replacing the app from the latest `.dmg`.
- **One workspace path at a time:** DevFlow is currently optimized around a single local workspace root.
- **PRs are created live:** there is no draft-PR path yet.
- **Team-scale features are not the focus yet:** today's experience is strongest for individual contributors working locally.

---

## Quick start

### For users

The first beta release is coming soon. Once it lands, you will be able to download the latest `.dmg` from the [Releases page](../../releases), move **DevFlow.app** into `/Applications`, and start from there.

Until then, the clearest way to try DevFlow is to run it from source using the repo.

Full walkthrough: [doc/getting-started-users.md](doc/getting-started-users.md)

### For developers

```sh
git clone <repo-url>
cd <repo-folder>
open DevFlow.xcodeproj
```

Then run the app with **⌘R** in Xcode.

Developer setup and validation: [doc/getting-started-developers.md](doc/getting-started-developers.md)

---

## Documentation map

- [doc/details.md](doc/details.md) — product overview, workflow, architecture, and boundaries
- [doc/getting-started-users.md](doc/getting-started-users.md) — installation, setup, everyday usage
- [doc/getting-started-developers.md](doc/getting-started-developers.md) — local development and release packaging
- [doc/ROADMAP.md](doc/ROADMAP.md) — now / next / later direction

---

## 🧭 Roadmap at a glance

The roadmap is organized around product expansion, not maintenance work:

- **Now:** deepen the core Jira-to-PR flow
- **Next:** sharpen review quality and PR readiness
- **Later:** expand team workflows and distribution polish
- **Exploring:** broader integrations and companion experiences

See [doc/ROADMAP.md](doc/ROADMAP.md) for the full breakdown.

---

## GitHub show-off ideas ✨

If you want this repository page to feel more alive, these are the highest-value upgrades:

- Add a short **20-30 second hero GIF** showing ticket → suggested change → PR creation.
- Add **2 or 3 annotated screenshots** for onboarding, ticket detail, and diff review.
- Use a small set of **badges or accent colors** only if they support clarity; one calm blue/teal accent will usually look better than a rainbow row.
- Create a **social preview image** that matches the app style so links look polished when shared.

These additions would make the GitHub page feel more premium without turning the README into marketing noise.

---

## Contributing

Pull requests are welcome. For larger changes, opening an issue first is a good idea. Start with [doc/getting-started-developers.md](doc/getting-started-developers.md).

## License

MIT License — see [LICENSE](LICENSE).
