import Foundation

enum ToolsTimelineReducer {
    static func toneForOperationStatus(_ status: String) -> StatusTone {
        let s = status.lowercased()
        if s.contains("succeed") || s.contains("done") {
            return .success
        }
        if s.contains("fail") || s.contains("error") {
            return .danger
        }
        if s.contains("running") || s.contains("pending") {
            return .warning
        }
        return .neutral
    }

    static func toneForEvent(_ event: OperationEventRecord) -> StatusTone {
        let eventType = event.eventType.lowercased()
        let message = (event.message ?? "").lowercased()
        if eventType.contains("error") || eventType.contains("fail") || message.contains("error") || message.contains("fail") {
            return .danger
        }
        if eventType.contains("succeed") || eventType.contains("done") || eventType.contains("complete") {
            return .success
        }
        if eventType.contains("start") || eventType.contains("progress") || eventType.contains("stage") {
            return .warning
        }
        return .neutral
    }

    static func appendTimeline(
        items: inout [ToolTimelineItem],
        title: String,
        detail: String,
        tone: StatusTone,
        timestampLabel: String,
        maxCount: Int = 80
    ) {
        let item = ToolTimelineItem(
            timestampLabel: timestampLabel,
            title: title,
            detail: detail,
            tone: tone
        )
        items.insert(item, at: 0)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
    }

    static func filteredEvents(
        from events: [OperationEventRecord],
        filter: ToolEventFilter,
        search: String
    ) -> [OperationEventRecord] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return events.filter { ev in
            if !term.isEmpty {
                let haystack = [ev.operationId, ev.timestampUtc, ev.eventType, ev.message ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(term) {
                    return false
                }
            }
            switch filter {
            case .all:
                return true
            case .milestones:
                let et = ev.eventType.lowercased()
                return et.contains("start") || et.contains("succeed") || et.contains("fail") || et.contains("complete")
            case .errors:
                let et = ev.eventType.lowercased()
                let msg = (ev.message ?? "").lowercased()
                return et.contains("error") || et.contains("fail") || msg.contains("error") || msg.contains("fail")
            }
        }
    }

    static func runStatus(from operationStatus: String) -> ToolRunStatus {
        let status = operationStatus.lowercased()
        if status.contains("fail") || status.contains("error") {
            return .failed
        }
        if status.contains("done") || status.contains("succeed") || status.contains("complete") {
            return .succeeded
        }
        if status.contains("running") || status.contains("pending") {
            return .running
        }
        return .idle
    }
}
