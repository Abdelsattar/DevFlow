import Foundation

/// Represents the current state of a ticket's workflow progression.
enum WorkflowState: String, Codable, Sendable {
    case idle
    case planning
    case planReady
    case implementing
    case implReady
    case reviewing
    case reviewReady
    case creatingPR
    case done
    case failed

    var displayName: String {
        switch self {
        case .idle:         return "Ready"
        case .planning:     return "Planning..."
        case .planReady:    return "Plan Ready"
        case .implementing: return "Implementing..."
        case .implReady:    return "Implementation Ready"
        case .reviewing:    return "Reviewing..."
        case .reviewReady:  return "Review Ready"
        case .creatingPR:   return "Creating PR..."
        case .done:         return "Done"
        case .failed:       return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .idle:         return "circle"
        case .planning:     return "brain"
        case .planReady:    return "checkmark.circle"
        case .implementing: return "hammer"
        case .implReady:    return "checkmark.circle.fill"
        case .reviewing:    return "eye"
        case .reviewReady:  return "checkmark.seal"
        case .creatingPR:   return "arrow.triangle.pull"
        case .done:         return "checkmark.seal.fill"
        case .failed:       return "xmark.circle"
        }
    }

    var canPlan: Bool {
        self == .idle || self == .failed
    }

    var canImplement: Bool {
        self == .planReady
    }

    var canReview: Bool {
        self == .implReady
    }

    var canCreatePR: Bool {
        self == .reviewReady
    }

    var isInProgress: Bool {
        switch self {
        case .planning, .implementing, .reviewing, .creatingPR:
            return true
        default:
            return false
        }
    }
}
