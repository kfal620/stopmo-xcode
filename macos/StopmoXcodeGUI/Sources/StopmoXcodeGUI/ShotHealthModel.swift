import Foundation

/// Shot-level health buckets used to summarize whether a shot is clean, inflight, or needs attention.
enum ShotHealthState: String, CaseIterable, Identifiable {
    case clean = "Clean"
    case issues = "Issues"
    case inflight = "Inflight"
    case queued = "Queued"

    var id: String { rawValue }

    var tone: StatusTone {
        switch self {
        case .clean:
            return .success
        case .issues:
            return .danger
        case .inflight:
            return .warning
        case .queued:
            return .neutral
        }
    }
}

/// Computed triage assessment for one shot, including delivery readiness and user-facing summary text.
struct ShotHealthEvaluation: Identifiable {
    let shot: ShotSummaryRow
    let healthState: ShotHealthState
    let isDeliverable: Bool
    let completionLabel: String
    let readinessReason: String?
    let issueSummary: String

    var id: String { shot.id }
}

/// Policy helpers that derive triage health state and delivery readiness from shot summary data.
enum ShotHealthModel {
    static func evaluate(_ shot: ShotSummaryRow) -> ShotHealthEvaluation {
        let healthState = healthState(for: shot)
        let deliverable = isDeliverable(shot)
        let completion = completionLabel(for: shot)
        let reason = deliverable ? nil : readinessReason(for: shot)
        return ShotHealthEvaluation(
            shot: shot,
            healthState: healthState,
            isDeliverable: deliverable,
            completionLabel: completion,
            readinessReason: reason,
            issueSummary: issueSummary(for: shot, healthState: healthState, isDeliverable: deliverable)
        )
    }

    static func evaluate(snapshot: ShotsSummarySnapshot?) -> [ShotHealthEvaluation] {
        guard let shots = snapshot?.shots else { return [] }
        return shots.map(evaluate(_:))
    }

    static func resolveActiveShot(from snapshot: ShotsSummarySnapshot?) -> ShotSummaryRow? {
        guard let shots = snapshot?.shots, !shots.isEmpty else {
            return nil
        }

        let processing = shots.filter { isInflightOrProcessing($0) }
        if let active = processing.sorted(by: compareForRecency).first {
            return active
        }
        return shots.sorted(by: compareForRecency).first
    }

    static func healthState(for shot: ShotSummaryRow) -> ShotHealthState {
        if isIssuesShot(shot) {
            return .issues
        }
        if isInflightOrProcessing(shot) {
            return .inflight
        }
        if isDoneShot(shot) {
            return .clean
        }
        return .queued
    }

    static func isDeliverable(_ shot: ShotSummaryRow) -> Bool {
        isDoneShot(shot)
    }

    static func completionLabel(for shot: ShotSummaryRow) -> String {
        if shot.totalFrames <= 0 {
            return "0/0 done"
        }
        return "\(shot.doneFrames)/\(shot.totalFrames) done"
    }

    static func readinessReason(for shot: ShotSummaryRow) -> String {
        if isIssuesShot(shot) {
            return "has issues"
        }
        if isInflightOrProcessing(shot) {
            return "inflight"
        }
        return "not complete"
    }

    static func issueSummary(for shot: ShotSummaryRow) -> String {
        issueSummary(
            for: shot,
            healthState: healthState(for: shot),
            isDeliverable: isDeliverable(shot)
        )
    }

    static func updatedDisplayLabel(for shot: ShotSummaryRow, now: Date = Date()) -> String {
        updatedDisplayLabel(for: shot.lastUpdatedAt, now: now)
    }

    static func updatedDisplayLabel(for timestamp: String?, now: Date = Date()) -> String {
        PathTimestampHelpers.relativeUpdatedLabel(timestamp, now: now)
    }

    private static func isIssuesShot(_ shot: ShotSummaryRow) -> Bool {
        if shot.failedFrames > 0 {
            return true
        }
        let stateLower = shot.state.lowercased()
        if stateLower.contains("issue") || stateLower.contains("fail") {
            return true
        }
        let assemblyLower = (shot.assemblyState ?? "").lowercased()
        return assemblyLower.contains("fail")
    }

    private static func isInflightOrProcessing(_ shot: ShotSummaryRow) -> Bool {
        if shot.inflightFrames > 0 {
            return true
        }
        let lower = shot.state.lowercased()
        return lower.contains("process") || lower == "processing"
    }

    private static func isDoneShot(_ shot: ShotSummaryRow) -> Bool {
        let stateLower = shot.state.lowercased()
        if stateLower == "done" {
            return true
        }
        return shot.totalFrames > 0
            && (shot.doneFrames + shot.failedFrames) >= shot.totalFrames
            && shot.failedFrames == 0
    }

    private static func compareForRecency(_ lhs: ShotSummaryRow, _ rhs: ShotSummaryRow) -> Bool {
        let left = lhs.lastUpdatedAt ?? ""
        let right = rhs.lastUpdatedAt ?? ""
        if left == right {
            return lhs.shotName.localizedCaseInsensitiveCompare(rhs.shotName) == .orderedAscending
        }
        return left > right
    }

    private static func issueSummary(
        for shot: ShotSummaryRow,
        healthState: ShotHealthState,
        isDeliverable: Bool
    ) -> String {
        if isDeliverable {
            return "Ready for delivery."
        }

        switch healthState {
        case .issues:
            if shot.failedFrames > 0 {
                return "\(shot.failedFrames) failed frame(s) need attention."
            }
            if let assemblyState = shot.assemblyState, !assemblyState.isEmpty {
                return "Assembly state: \(assemblyState)."
            }
            return "Shot reported issues that need review."
        case .inflight:
            if shot.inflightFrames > 0 {
                return "\(shot.inflightFrames) frame(s) still converting."
            }
            return "Shot is still processing."
        case .queued:
            if shot.totalFrames == 0 {
                return "Waiting for the first converted frames."
            }
            return "Shot is not complete yet."
        case .clean:
            return "Ready for delivery."
        }
    }

}
