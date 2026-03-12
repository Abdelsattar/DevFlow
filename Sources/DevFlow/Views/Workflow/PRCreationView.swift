import SwiftUI

/// Flow state for the PR creation pipeline.
enum PRCreationStep: Equatable {
    case configure     // User edits title, body, base branch
    case pushing       // Pushing branch to remote
    case creatingPR    // Creating the PR via GitHub API
    case updatingJira  // Transitioning JIRA + adding PR link comment
    case done          // All steps complete
    case failed(String) // Something went wrong
}

/// A full-screen view that guides the user through:
///   1. Configure PR title, body, base branch
///   2. Push branch to remote
///   3. Create PR on GitHub
///   4. Transition JIRA ticket + add PR link as comment
struct PRCreationView: View {
    @Environment(AppState.self) private var appState
    let ticket: JiraTicket
    let changeSet: ChangeSet

    @State private var step: PRCreationStep = .configure
    @State private var prTitle: String = ""
    @State private var prBody: String = ""
    @State private var baseBranch: String = "master"
    @State private var headBranch: String = ""
    @State private var transitionJira: Bool = true
    @State private var addJiraComment: Bool = true
    @State private var targetJiraStatus: String = "In Review"
    @State private var createdPR: GitHubPullRequest?
    @State private var repoOwner: String = ""
    @State private var repoName: String = ""
    @State private var stepLog: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch step {
            case .configure:
                configureForm
            case .pushing, .creatingPR, .updatingJira:
                progressView
            case .done:
                successView
            case .failed(let message):
                failureView(message)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task { await loadDefaults() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .font(.title3)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Create Pull Request")
                    .font(.headline)
                Text("\(ticket.key): \(ticket.fields.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            stepIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            stepDot(active: step == .configure, done: isStepDone(.configure))
                .accessibilityLabel("Configure: \(stepDotStatus(.configure))")
            stepDot(active: step == .pushing, done: isStepDone(.pushing))
                .accessibilityLabel("Push: \(stepDotStatus(.pushing))")
            stepDot(active: step == .creatingPR, done: isStepDone(.creatingPR))
                .accessibilityLabel("Create PR: \(stepDotStatus(.creatingPR))")
            stepDot(active: step == .updatingJira, done: isStepDone(.updatingJira))
                .accessibilityLabel("Update JIRA: \(stepDotStatus(.updatingJira))")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PR creation progress")
    }

    private func stepDotStatus(_ s: PRCreationStep) -> String {
        if isStepDone(s) { return "complete" }
        if step == s { return "in progress" }
        return "pending"
    }

    private func stepDot(active: Bool, done: Bool) -> some View {
        Circle()
            .fill(done ? Color.green : (active ? Color.accentColor : Color.secondary.opacity(0.3)))
            .frame(width: 8, height: 8)
    }

    private func isStepDone(_ s: PRCreationStep) -> Bool {
        let order: [PRCreationStep] = [.configure, .pushing, .creatingPR, .updatingJira, .done]
        guard let currentIdx = order.firstIndex(of: step),
              let checkIdx = order.firstIndex(of: s) else { return false }
        return checkIdx < currentIdx
    }

    // MARK: - Configure Form

    private var configureForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Branch info
                GroupBox("Branch") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Head (your branch)") {
                            Text(headBranch.isEmpty ? "loading..." : headBranch)
                                .fontDesign(.monospaced)
                                .font(.caption)
                        }

                        LabeledContent("Base (merge into)") {
                            TextField("Base branch", text: $baseBranch)
                                .textFieldStyle(.roundedBorder)
                                .fontDesign(.monospaced)
                                .font(.caption)
                                .frame(maxWidth: 200)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // PR details
                GroupBox("Pull Request") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("PR title", text: $prTitle)
                            .textFieldStyle(.roundedBorder)

                        Text("Body")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $prBody)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 120, maxHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.vertical, 4)
                }

                // JIRA options
                GroupBox("JIRA Integration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Transition ticket status", isOn: $transitionJira)
                        if transitionJira {
                            LabeledContent("Target status") {
                                TextField("Status", text: $targetJiraStatus)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 200)
                            }
                            .padding(.leading, 20)
                        }

                        Toggle("Add PR link as JIRA comment", isOn: $addJiraComment)
                    }
                    .padding(.vertical, 4)
                }

                // Repository info
                if !repoOwner.isEmpty {
                    GroupBox("Repository") {
                        LabeledContent("Repository") {
                            Text("\(repoOwner)/\(repoName)")
                                .fontDesign(.monospaced)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Create PR button
                HStack {
                    Spacer()
                    Button {
                        Task { await executePRPipeline() }
                    } label: {
                        Label("Create Pull Request", systemImage: "arrow.triangle.pull")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(!canCreate)
                    .accessibilityLabel("Create pull request")
                    .accessibilityHint("Push branch and create PR for \(ticket.key)")
                }
            }
            .padding(16)
        }
    }

    private var canCreate: Bool {
        !prTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !headBranch.isEmpty
        && !baseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !repoOwner.isEmpty
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text(stepLabel)
                .font(.headline)

            // Step log
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stepLog.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(entry)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 300, alignment: .leading)

            Spacer()
        }
        .padding(20)
    }

    private var stepLabel: String {
        switch step {
        case .pushing: "Pushing branch to remote..."
        case .creatingPR: "Creating pull request..."
        case .updatingJira: "Updating JIRA ticket..."
        default: ""
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Pull Request Created!")
                .font(.title2)
                .fontWeight(.semibold)

            if let pr = createdPR {
                VStack(spacing: 8) {
                    Text("#\(pr.number): \(pr.title)")
                        .font(.headline)

                    // Clickable URL
                    if let prURL = URL(string: pr.htmlUrl) {
                        Link(destination: prURL) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text(pr.htmlUrl)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                    } else {
                        Text(pr.htmlUrl)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.secondary.opacity(0.05))
                .cornerRadius(8)
            }

            // Completed steps log
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stepLog.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(entry)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Failure View

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Steps completed so far
            if !stepLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(stepLog.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(entry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button("Try Again") {
                step = .configure
                stepLog = []
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Load Defaults

    private func loadDefaults() async {
        let repoPath = appState.workspacePath

        // Get current branch
        do {
            headBranch = try await appState.gitClient.currentBranch(at: repoPath)
        } catch {
            headBranch = changeSet.branchName
        }

        // Get remote URL and parse owner/repo
        do {
            let remoteURL = try await appState.gitClient.remoteURL(at: repoPath)
            if let parsed = GitHubService.parseRemoteURL(remoteURL) {
                repoOwner = parsed.owner
                repoName = parsed.name
            }
        } catch {
            // User will need to configure manually or we'll fail later
        }

        // Default PR title: "TICKET-KEY: Summary"
        prTitle = GitClient.commitMessage(ticketKey: ticket.key, description: ticket.fields.summary)

        // Default PR body with JIRA link
        prBody = GitHubService.buildPRBody(
            ticketKey: ticket.key,
            summary: ticket.fields.summary,
            changeSummary: buildChangeSummary(),
            jiraBaseURL: appState.jiraBaseURL
        )

        // Try to detect default branch
        do {
            let repo = try await appState.githubService.getRepository(owner: repoOwner, name: repoName)
            baseBranch = repo.defaultBranch
        } catch {
            // Keep "master" as default
        }
    }

    private func buildChangeSummary() -> String {
        let applied = changeSet.changes.filter(\.isApplied)
        if applied.isEmpty { return "" }

        return applied.map { change in
            "- \(change.changeType.displayName): `\(change.filePath)`"
        }.joined(separator: "\n")
    }

    // MARK: - Execute Pipeline

    private func executePRPipeline() async {
        step = .pushing

        let config = PRPipelineConfig(
            prTitle: prTitle,
            prBody: prBody,
            baseBranch: baseBranch,
            transitionJira: transitionJira,
            targetJiraStatus: targetJiraStatus,
            addJiraComment: addJiraComment
        )

        do {
            let result = try await PRPipelineService.executePRPipeline(
                ticket: ticket,
                config: config,
                repoPath: appState.workspacePath,
                gitClient: appState.gitClient,
                githubService: appState.githubService,
                jiraService: appState.jiraService
            )

            createdPR = result.pullRequest
            stepLog = result.stepLog

            NotificationService.shared.notifyPRCreated(
                ticketKey: ticket.key,
                prNumber: result.pullRequest.number,
                prURL: result.pullRequest.htmlUrl
            )

            step = .done
        } catch let error as PRPipelineError {
            switch error {
            case .pushFailed(let reason):
                step = .failed("Push failed: \(reason)")
                NotificationService.shared.notifyError(
                    title: "Push Failed",
                    message: "\(ticket.key): \(reason)"
                )
            case .prCreationFailed(let reason):
                step = .failed("PR creation failed: \(reason)")
                NotificationService.shared.notifyError(
                    title: "PR Creation Failed",
                    message: "\(ticket.key): \(reason)"
                )
            case .cannotResolveRepo(let reason):
                step = .failed("Cannot resolve repo: \(reason)")
            }
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
}
