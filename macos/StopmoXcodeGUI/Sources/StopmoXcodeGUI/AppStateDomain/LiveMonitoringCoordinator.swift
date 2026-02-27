import Foundation

@MainActor
/// Protocol defining live monitoring coordinating behavior.
protocol LiveMonitoringCoordinating: AnyObject {
    var sessionToken: UUID { get }
    var isRunning: Bool { get }
    func start(
        force: Bool,
        onStarted: @escaping (UUID) -> Void,
        onStopped: @escaping () -> Void,
        pollInterval: @escaping () -> Double,
        refresh: @escaping (UUID) async -> Bool
    )
    func stop(onStopped: @escaping () -> Void)
}

@MainActor
/// Coordinator for live monitoring coordinator.
final class LiveMonitoringCoordinator: LiveMonitoringCoordinating {
    private var monitorTask: Task<Void, Never>?
    private(set) var sessionToken = UUID()

    var isRunning: Bool {
        monitorTask != nil
    }

    deinit {
        monitorTask?.cancel()
    }

    func start(
        force: Bool,
        onStarted: @escaping (UUID) -> Void,
        onStopped: @escaping () -> Void,
        pollInterval: @escaping () -> Double,
        refresh: @escaping (UUID) async -> Bool
    ) {
        if isRunning, !force {
            return
        }

        stop(onStopped: onStopped)
        sessionToken = UUID()
        let token = sessionToken
        onStarted(token)

        monitorTask = Task { [weak self] in
            let firstPass = await refresh(token)
            guard firstPass else {
                await MainActor.run {
                    guard let self else { return }
                    if self.sessionToken == token {
                        self.stop(onStopped: onStopped)
                    }
                }
                return
            }

            while !Task.isCancelled {
                let interval = await MainActor.run { max(0.5, pollInterval()) }
                let nanos = UInt64(interval * 1_000_000_000.0)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    break
                }
                if Task.isCancelled {
                    break
                }
                let shouldContinue = await refresh(token)
                if !shouldContinue {
                    break
                }
            }

            await MainActor.run {
                guard let self else { return }
                if self.sessionToken == token {
                    self.stop(onStopped: onStopped)
                }
            }
        }
    }

    func stop(onStopped: @escaping () -> Void) {
        monitorTask?.cancel()
        monitorTask = nil
        sessionToken = UUID()
        onStopped()
    }
}
