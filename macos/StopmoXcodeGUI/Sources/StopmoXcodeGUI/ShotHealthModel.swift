import Foundation

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

struct ShotHealthEvaluation: Identifiable {
    let shot: ShotSummaryRow
    let healthState: ShotHealthState
    let isDeliverable: Bool
    let completionLabel: String
    let readinessReason: String?

    var id: String { shot.id }
}

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
            readinessReason: reason
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

    static func updatedDisplayLabel(for shot: ShotSummaryRow, now: Date = Date()) -> String {
        updatedDisplayLabel(for: shot.lastUpdatedAt, now: now)
    }

    static func updatedDisplayLabel(for timestamp: String?, now: Date = Date()) -> String {
        guard let timestamp = timestamp?.trimmingCharacters(in: .whitespacesAndNewlines),
              !timestamp.isEmpty,
              let date = parseTimestamp(timestamp)
        else {
            return "Updated -"
        }

        let delta = max(0, Int(now.timeIntervalSince(date)))
        if delta < 5 {
            return "Updated now"
        }
        if delta < 60 {
            return "Updated \(delta)s ago"
        }
        if delta < 3600 {
            return "Updated \(delta / 60)m ago"
        }
        if delta < 86_400 {
            let hours = delta / 3600
            let minutes = (delta % 3600) / 60
            if minutes == 0 {
                return "Updated \(hours)h ago"
            }
            return "Updated \(hours)h \(minutes)m ago"
        }
        let days = delta / 86_400
        return "Updated \(days)d ago"
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

    private static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
    }
}
