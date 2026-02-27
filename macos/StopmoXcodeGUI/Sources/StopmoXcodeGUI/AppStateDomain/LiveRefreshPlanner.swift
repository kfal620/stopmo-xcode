import Foundation

struct LiveSnapshotFetchLimits: Equatable {
    let queueLimit: Int
    let logTailLines: Int
    let includeShots: Bool
    let shotsLimit: Int
}

enum LiveRefreshPlanner {
    static func refreshKind(
        selectedHub: LifecycleHub,
        selectedConfigurePanel: ConfigurePanel,
        selectedTriagePanel: TriagePanel,
        selectedDeliverPanel: DeliverPanel
    ) -> AppState.RefreshKind {
        switch selectedHub {
        case .configure:
            switch selectedConfigurePanel {
            case .workspaceHealth:
                return .health
            case .projectSettings, .calibration:
                return .config
            }
        case .capture:
            return .live
        case .triage:
            switch selectedTriagePanel {
            case .shots, .queue:
                return .live
            case .diagnostics:
                return .logs
            }
        case .deliver:
            switch selectedDeliverPanel {
            case .dayWrap:
                return .dayWrap
            case .runHistory:
                return .history
            }
        }
    }

    static func shouldMonitor(
        selectedHub: LifecycleHub,
        selectedTriagePanel: TriagePanel
    ) -> Bool {
        switch selectedHub {
        case .capture:
            return true
        case .triage:
            return selectedTriagePanel == .shots || selectedTriagePanel == .queue
        case .configure, .deliver:
            return false
        }
    }

    static func snapshotFetchLimits(
        selectedHub: LifecycleHub,
        selectedTriagePanel: TriagePanel
    ) -> LiveSnapshotFetchLimits {
        switch selectedHub {
        case .capture:
            return LiveSnapshotFetchLimits(queueLimit: 220, logTailLines: 60, includeShots: true, shotsLimit: 120)
        case .triage:
            switch selectedTriagePanel {
            case .queue:
                return LiveSnapshotFetchLimits(queueLimit: 350, logTailLines: 40, includeShots: false, shotsLimit: 0)
            case .shots:
                return LiveSnapshotFetchLimits(queueLimit: 260, logTailLines: 30, includeShots: true, shotsLimit: 500)
            case .diagnostics:
                return LiveSnapshotFetchLimits(queueLimit: 220, logTailLines: 40, includeShots: false, shotsLimit: 0)
            }
        case .configure, .deliver:
            return LiveSnapshotFetchLimits(queueLimit: 220, logTailLines: 40, includeShots: false, shotsLimit: 0)
        }
    }
}
