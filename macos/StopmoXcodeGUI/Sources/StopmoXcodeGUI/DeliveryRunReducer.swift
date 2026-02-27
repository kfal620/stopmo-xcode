import Foundation

/// Pure helpers for evolving delivery run state and event history.
enum DeliveryRunReducer {
    static func begin(kind: DeliveryRunKind, total: Int, label: String, nowUtc: String) -> DeliveryRunState {
        let clampedTotal = max(0, total)
        return DeliveryRunState(
            kind: kind,
            status: .running,
            total: clampedTotal,
            completed: 0,
            failed: 0,
            activeLabel: label,
            progress: 0.0,
            latestOutputs: [],
            events: [],
            startedAtUtc: nowUtc,
            finishedAtUtc: nil
        )
    }

    static func appendEvent(
        state: inout DeliveryRunState,
        tone: DeliveryRunEventTone,
        title: String,
        detail: String,
        shotName: String?,
        timestampUtc: String,
        maxEvents: Int
    ) {
        let event = DeliveryRunEvent(
            id: UUID().uuidString,
            timestampUtc: timestampUtc,
            tone: tone,
            title: title,
            detail: detail,
            shotName: shotName
        )
        state.events.insert(event, at: 0)
        if state.events.count > max(1, maxEvents) {
            state.events = Array(state.events.prefix(maxEvents))
        }
    }

    static func updateProgress(state: inout DeliveryRunState, completed: Int, failed: Int, activeLabel: String) {
        let clampedCompleted = max(0, completed)
        let clampedFailed = max(0, failed)
        let processed = clampedCompleted + clampedFailed
        let total = max(state.total, processed)

        state.completed = clampedCompleted
        state.failed = clampedFailed
        state.total = total
        state.activeLabel = activeLabel
        if total > 0 {
            state.progress = min(1.0, max(0.0, Double(processed) / Double(total)))
        } else {
            state.progress = 0.0
        }
    }

    static func finish(
        state: inout DeliveryRunState,
        status: DeliveryRunStatus,
        outputs: [String],
        completed: Int?,
        total: Int?,
        failed: Int?,
        activeLabel: String?,
        nowUtc: String
    ) {
        if let completed {
            state.completed = max(0, completed)
        }
        if let failed {
            state.failed = max(0, failed)
        }
        if let total {
            state.total = max(0, total)
        }
        if let activeLabel {
            state.activeLabel = activeLabel
        }

        let processed = state.completed + state.failed
        if state.total > 0 {
            state.progress = min(1.0, max(0.0, Double(processed) / Double(state.total)))
        } else {
            state.progress = status == .succeeded ? 1.0 : 0.0
        }

        state.status = status
        state.latestOutputs = outputs
        state.finishedAtUtc = nowUtc
    }

    static func pruneSelection(_ selected: Set<String>, snapshot: ShotsSummarySnapshot?) -> Set<String> {
        let deliverable = Set(
            ShotHealthModel
                .evaluate(snapshot: snapshot)
                .filter(\.isDeliverable)
                .map { $0.shot.shotName }
        )
        return selected.intersection(deliverable)
    }
}
