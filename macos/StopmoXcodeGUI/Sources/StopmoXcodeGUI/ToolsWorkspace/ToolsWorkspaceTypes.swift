import Foundation

enum ToolKind: String, CaseIterable {
    case transcodeOne = "Transcode One"
    case suggestMatrix = "Suggest Matrix"
    case dpxToProres = "DPX To ProRes"
}

enum ToolsMode: String, CaseIterable {
    case all
    case utilitiesOnly
    case deliveryOnly
}

enum DeliveryPresentation: String, CaseIterable {
    case full
    case diagnosticsOnly
}

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

enum ToolEventFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case milestones = "Milestones"
    case errors = "Errors"

    var id: String { rawValue }
}

struct ToolPreflight {
    let blockers: [String]
    let warnings: [String]

    var ok: Bool { blockers.isEmpty }
}

struct ToolTimelineItem: Identifiable {
    let id = UUID()
    let timestampLabel: String
    let title: String
    let detail: String
    let tone: StatusTone
}

struct ToolsWorkspaceContext {
    let tabs: [ToolsTab]
    let defaultTab: ToolsTab
    let headerTitle: String
    let headerSubtitle: String
    let showEmbeddedHeaderChips: Bool
}
