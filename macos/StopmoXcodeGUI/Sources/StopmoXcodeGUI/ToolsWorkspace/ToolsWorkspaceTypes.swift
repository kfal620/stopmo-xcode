import Foundation

/// Backend tool operation kinds supported by the tools workspace.
enum ToolKind: String, CaseIterable {
    case transcodeOne = "Transcode One"
    case suggestMatrix = "Suggest Matrix"
    case dpxToProres = "DPX To ProRes"
}

/// High-level tools workspace modes used by hosting screens.
enum ToolsMode: String, CaseIterable {
    case all
    case utilitiesOnly
    case deliveryOnly
}

/// Delivery workspace presentation variants for tools embedding.
enum DeliveryPresentation: String, CaseIterable {
    case full
    case diagnosticsOnly
}

/// Tab identifiers available within the tools workspace UI.
enum ToolsTab: String, CaseIterable, Identifiable {
    case transcode = "Transcode"
    case matrix = "Matrix"
    case dpxProres = "DPX -> ProRes"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .transcode:
            return "photo"
        case .matrix:
            return "square.grid.3x3"
        case .dpxProres:
            return "film.stack"
        case .diagnostics:
            return "waveform.path.ecg"
        }
    }
}

/// Last-run status used for tool execution indicators.
enum ToolRunStatus: Equatable {
    case idle
    case running
    case succeeded
    case failed

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }

    var tone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .running:
            return .warning
        case .succeeded:
            return .success
        case .failed:
            return .danger
        }
    }
}

/// Event stream filters used in tools diagnostics timeline.
enum ToolEventFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case milestones = "Milestones"
    case errors = "Errors"

    var id: String { rawValue }
}

/// Preflight validation output containing blockers and warnings.
struct ToolPreflight {
    let blockers: [String]
    let warnings: [String]

    var ok: Bool { blockers.isEmpty }
}

/// Render-ready timeline row for tools operation history.
struct ToolTimelineItem: Identifiable {
    let id = UUID()
    let timestampLabel: String
    let title: String
    let detail: String
    let tone: StatusTone
}

/// Resolved tab/header context for current tools workspace mode.
struct ToolsWorkspaceContext {
    let tabs: [ToolsTab]
    let defaultTab: ToolsTab
    let headerTitle: String
    let headerSubtitle: String
    let showEmbeddedHeaderChips: Bool
}
