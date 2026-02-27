import Foundation

struct LiveTelemetryUpdate {
    let throughputFramesPerMinute: Double
    let lastFrameAt: Date?
    let lastDoneFrameCountSample: Int?
    let lastRateSampleAt: Date?
    let queueDepthTrend: [Int]
}

enum LiveTelemetryReducer {
    static func updateTelemetry(
        watchState: WatchServiceState,
        counts: [String: Int],
        previousDoneFrameCount: Int?,
        previousSampleAt: Date?,
        previousLastFrameAt: Date?,
        previousThroughput: Double,
        previousQueueDepthTrend: [Int],
        now: Date
    ) -> LiveTelemetryUpdate {
        let doneCount = counts["done", default: watchState.completedFrames]
        var throughput = previousThroughput
        var lastFrameAt = previousLastFrameAt

        if let prevDone = previousDoneFrameCount,
           let prevAt = previousSampleAt
        {
            let deltaDone = max(0, doneCount - prevDone)
            let deltaSeconds = now.timeIntervalSince(prevAt)
            if deltaSeconds > 0.05 {
                throughput = (Double(deltaDone) / deltaSeconds) * 60.0
            }
            if deltaDone > 0 {
                lastFrameAt = now
            }
        } else if doneCount > 0 {
            lastFrameAt = now
            throughput = 0.0
        }

        let depth = counts["detected", default: 0]
            + counts["decoding", default: 0]
            + counts["xform", default: 0]
            + counts["dpx_write", default: 0]
        var queueDepthTrend = previousQueueDepthTrend
        queueDepthTrend.append(depth)
        if queueDepthTrend.count > 180 {
            queueDepthTrend = Array(queueDepthTrend.suffix(180))
        }

        return LiveTelemetryUpdate(
            throughputFramesPerMinute: throughput,
            lastFrameAt: lastFrameAt,
            lastDoneFrameCountSample: doneCount,
            lastRateSampleAt: now,
            queueDepthTrend: queueDepthTrend
        )
    }

    static func recordLiveEvent(
        existingEvents: [String],
        message: String,
        timestamp: String,
        maxEvents: Int
    ) -> [String] {
        var events = existingEvents
        events.insert("[\(timestamp)] \(message)", at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
        return events
    }
}
