import Foundation

// MARK: - GitHub User

/// Represents a GitHub user from the REST API.
struct GitHubUser: Codable, Sendable {
    let id: Int
    let login: String
    let name: String?
    let email: String?
    let avatarUrl: String?
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, login, name, email
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
    }
}

// MARK: - GitHub Organization

/// Represents a GitHub organization from the REST API.
struct GitHubOrganization: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let login: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, login, description
    }
}

// MARK: - GitHub Repository

/// Represents a GitHub repository from the REST API.
struct GitHubRepository: Codable, Sendable {
    let id: Int
    let name: String
    let fullName: String
    let owner: GitHubRepoOwner
    let htmlUrl: String
    let cloneUrl: String?
    let sshUrl: String?
    let defaultBranch: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, owner
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
        case sshUrl = "ssh_url"
        case defaultBranch = "default_branch"
        case isPrivate = "private"
    }
}

/// Owner of a GitHub repository.
struct GitHubRepoOwner: Codable, Sendable {
    let login: String
    let id: Int
}

// MARK: - GitHub Pull Request

/// Represents a pull request from the GitHub REST API.
struct GitHubPullRequest: Codable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlUrl: String
    let head: GitHubPRRef
    let base: GitHubPRRef
    let user: GitHubUser?
    let createdAt: String?
    let updatedAt: String?
    let merged: Bool?
    let mergeable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, head, base, user, merged, mergeable
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A branch reference in a pull request (head or base).
struct GitHubPRRef: Codable, Sendable {
    let ref: String
    let sha: String
    let label: String?
}

// MARK: - PR Creation Request

/// Body payload for creating a pull request via the GitHub API.
struct CreatePullRequestBody: Codable, Sendable {
    let title: String
    let body: String
    let head: String
    let base: String
}
