import Foundation

/// Filter controls used by the embedded capture activity console.
enum CaptureActivityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case warnings = "Warnings"
    case errors = "Errors"
    case system = "System"

    var id: String { rawValue }
}

/// Parsed severity bucket for one capture activity row.
enum CaptureActivitySeverity: String {
    case info
    case warning
    case error
    case system
}

/// Parsed activity row used by the capture monitor console presentation.
struct CaptureActivityRow: Equatable {
    var timestamp: String?
    var message: String
    var severity: CaptureActivitySeverity
    var rawLine: String
}

/// One metric rendered inside a grouped KPI tile section.
struct CaptureKPIMetric: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    var tone: StatusTone
}

/// Group of KPI metrics for the capture monitor grouped-tile layout.
struct CaptureKPIGroup: Identifiable, Equatable {
    var id: String
    var title: String
    var metrics: [CaptureKPIMetric]
}

/// Pure formatting and mapping helpers for embedded capture monitor UI.
enum CaptureMonitorFormatting {
    static func parseActivityLine(_ line: String) -> CaptureActivityRow {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CaptureActivityRow(
                timestamp: nil,
                message: "",
                severity: .info,
                rawLine: line
            )
        }

        var timestamp: String?
        var message = trimmed
        if let closeBracket = trimmed.firstIndex(of: "]"),
           trimmed.hasPrefix("[")
        {
            let open = trimmed.index(after: trimmed.startIndex)
            let stamp = String(trimmed[open..<closeBracket]).trimmingCharacters(in: .whitespaces)
            if looksLikeClockTime(stamp) {
                timestamp = stamp
                let remainderStart = trimmed.index(after: closeBracket)
                message = String(trimmed[remainderStart...]).trimmingCharacters(in: .whitespaces)
            }
        }

        let resolvedMessage = message.isEmpty ? trimmed : message
        return CaptureActivityRow(
            timestamp: timestamp,
            message: resolvedMessage,
            severity: inferSeverity(for: resolvedMessage),
            rawLine: line
        )
    }

    static func inferSeverity(for message: String) -> CaptureActivitySeverity {
        let lower = message.lowercased()
        if lower.contains("error") || lower.contains("failed") {
            return .error
        }
        if lower.contains("warning") || lower.contains("blocked") || lower.contains("missing") {
            return .warning
        }
        if lower.contains("watch process")
            || lower.contains("queue counts updated")
            || lower.contains("monitoring")
            || lower.contains("service started")
            || lower.contains("service stopped")
            || lower.contains("watch service")
        {
            return .system
        }
        return .info
    }

    static func filterActivityRows(
        _ rows: [CaptureActivityRow],
        filter: CaptureActivityFilter,
        searchTerm: String
    ) -> [CaptureActivityRow] {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            if !term.isEmpty {
                let matchesMessage = row.message.localizedCaseInsensitiveContains(term)
                let matchesTimestamp = (row.timestamp ?? "").localizedCaseInsensitiveContains(term)
                if !matchesMessage && !matchesTimestamp {
                    return false
                }
            }

            switch filter {
            case .all:
                return true
            case .warnings:
                return row.severity == .warning
            case .errors:
                return row.severity == .error
            case .system:
                return row.severity == .system
            }
        }
    }

    static func groupedKPIs(
        queueCounts: [String: Int],
        throughputFramesPerMinute: Double,
        workersInFlight: Int,
        maxWorkers: Int,
        etaLabel: String,
        lastFrameLabel: String,
        hasLastFrame: Bool
    ) -> [CaptureKPIGroup] {
        let detected = queueCounts["detected", default: 0]
        let decoding = queueCounts["decoding", default: 0]
        let transform = queueCounts["xform", default: 0]
        let dpxWrite = queueCounts["dpx_write", default: 0]
        let done = queueCounts["done", default: 0]
        let failed = queueCounts["failed", default: 0]

        let safeMaxWorkers = max(1, maxWorkers)
        let workerTone: StatusTone = workersInFlight >= safeMaxWorkers ? .warning : .neutral
        let throughputLabel = String(format: "%.1f frames/min", throughputFramesPerMinute)
        let throughputTone: StatusTone = throughputFramesPerMinute > 0.01 ? .success : .warning
        let etaTone: StatusTone = etaLabel.contains("--") ? .warning : .neutral
        let lastFrameTone: StatusTone = hasLastFrame ? .neutral : .warning

        return [
            CaptureKPIGroup(
                id: "pipeline",
                title: "Pipeline Stages",
                metrics: [
                    metric(id: "detected", label: "Detected", value: "\(detected)", tone: .neutral),
                    metric(id: "decoding", label: "Decoding", value: "\(decoding)", tone: .neutral),
                    metric(id: "transform", label: "Transform", value: "\(transform)", tone: .neutral),
                    metric(id: "dpxWrite", label: "DPX Write", value: "\(dpxWrite)", tone: .neutral),
                ]
            ),
            CaptureKPIGroup(
                id: "outputPace",
                title: "Output & Pace",
                metrics: [
                    metric(id: "done", label: "Done", value: "\(done)", tone: done > 0 ? .success : .neutral),
                    metric(id: "failed", label: "Failed", value: "\(failed)", tone: failed > 0 ? .danger : .neutral),
                    metric(id: "throughput", label: "Throughput", value: throughputLabel, tone: throughputTone),
                ]
            ),
            CaptureKPIGroup(
                id: "capacityFreshness",
                title: "Capacity & Freshness",
                metrics: [
                    metric(
                        id: "workers",
                        label: "Workers",
                        value: "\(workersInFlight)/\(safeMaxWorkers)",
                        tone: workerTone
                    ),
                    metric(id: "eta", label: "ETA", value: etaLabel, tone: etaTone),
                    metric(id: "lastFrame", label: "Last Frame", value: lastFrameLabel, tone: lastFrameTone),
                ]
            ),
        ]
    }

    private static func metric(
        id: String,
        label: String,
        value: String,
        tone: StatusTone
    ) -> CaptureKPIMetric {
        CaptureKPIMetric(id: id, label: label, value: value, tone: tone)
    }

    private static func looksLikeClockTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 3 else {
            return false
        }
        return parts.allSatisfy { part in
            part.count == 2 && part.allSatisfy { $0.isNumber }
        }
    }
}
