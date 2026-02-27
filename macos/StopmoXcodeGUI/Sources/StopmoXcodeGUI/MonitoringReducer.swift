import Foundation

/// Monitoring transition output after a successful poll cycle.
struct MonitoringSuccessState {
    let consecutiveFailures: Int
    let pollIntervalSeconds: Double
    let lastSuccessAt: Date
}

/// Monitoring transition output after a failed poll cycle.
struct MonitoringFailureState {
    let consecutiveFailures: Int
    let pollIntervalSeconds: Double
    let nextPollAt: Date
    let shouldEmitDegradedWarning: Bool
}

/// Polling/backoff policy helpers for live monitoring state transitions.
enum MonitoringReducer {
    static func successTransition(
        watchState: WatchServiceState,
        now: Date
    ) -> MonitoringSuccessState {
        MonitoringSuccessState(
            consecutiveFailures: 0,
            pollIntervalSeconds: preferredSuccessPollInterval(using: watchState),
            lastSuccessAt: now
        )
    }

    static func failureTransition(
        previousFailures: Int,
        now: Date
    ) -> MonitoringFailureState {
        let failures = previousFailures + 1
        let interval = preferredFailurePollInterval(for: failures)
        let shouldWarn = failures >= 3
        return MonitoringFailureState(
            consecutiveFailures: failures,
            pollIntervalSeconds: interval,
            nextPollAt: now.addingTimeInterval(interval),
            shouldEmitDegradedWarning: shouldWarn
        )
    }

    static func preferredSuccessPollInterval(using watchState: WatchServiceState) -> Double {
        let counts = watchState.queue.counts
        let queueDepth = counts["detected", default: 0]
            + counts["decoding", default: 0]
            + counts["xform", default: 0]
            + counts["dpx_write", default: 0]
        if watchState.running || queueDepth > 0 || watchState.inflightFrames > 0 {
            return 1.0
        }
        return 2.5
    }

    static func preferredFailurePollInterval(for failureCount: Int) -> Double {
        let backoff = pow(2.0, Double(min(max(1, failureCount), 4)))
        return min(12.0, max(1.0, backoff))
    }
}
