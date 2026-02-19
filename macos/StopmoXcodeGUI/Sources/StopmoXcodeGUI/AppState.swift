import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: AppSection? = .setup
    @Published var repoRoot: String
    @Published var configPath: String
    @Published var config: StopmoConfigDocument = .empty
    @Published var health: BridgeHealth?
    @Published var watchServiceState: WatchServiceState?
    @Published var queueSnapshot: QueueSnapshot?
    @Published var shotsSnapshot: ShotsSummarySnapshot?
    @Published var configValidation: ConfigValidationSnapshot?
    @Published var watchPreflight: WatchPreflight?
    @Published var logsDiagnostics: LogsDiagnosticsSnapshot?
    @Published var historySummary: HistorySummarySnapshot?
    @Published var lastDiagnosticsBundlePath: String?
    @Published var liveEvents: [String] = []
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private var monitorTask: Task<Void, Never>?
    private var lastQueueCounts: [String: Int] = [:]
    private var lastWatchRunning: Bool?

    init() {
        let envRoot = ProcessInfo.processInfo.environment["STOPMO_XCODE_ROOT"]
        let root: String
        if let envRoot, !envRoot.isEmpty {
            root = envRoot
        } else {
            root = FileManager.default.currentDirectoryPath
        }
        repoRoot = root
        configPath = "\(root)/config/sample.yaml"
    }

    deinit {
        monitorTask?.cancel()
    }

    func refreshHealth() async {
        await runBlockingTask(label: "Checking runtime health") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().health(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.health = result
            self.statusMessage = "Health check completed"
        }
    }

    func loadConfig() async {
        await runBlockingTask(label: "Loading config") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let loaded = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().readConfig(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.config = loaded
            if let loadedPath = loaded.configPath {
                self.configPath = loadedPath
            }
            self.statusMessage = "Loaded config"
        }
    }

    func saveConfig() async {
        await runBlockingTask(label: "Saving config") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let payload = self.config
            let saved = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().writeConfig(repoRoot: repoRoot, configPath: configPath, config: payload)
            }.value
            self.config = saved
            self.statusMessage = "Saved config"
        }
    }

    func startWatchService() async {
        await runBlockingTask(label: "Starting watch service") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let watchState = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().watchStart(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.applyLiveSnapshots(watchState: watchState, shots: self.shotsSnapshot)
            if watchState.startBlocked == true {
                self.recordLiveEvent("Watch start blocked by preflight")
                self.statusMessage = "Watch start blocked"
            } else if let launchError = watchState.launchError, !launchError.isEmpty {
                self.recordLiveEvent("Watch start failed: \(launchError)")
                self.statusMessage = "Watch start failed"
            } else {
                self.recordLiveEvent("Watch service started")
                self.statusMessage = "Watch service running"
            }
            self.watchPreflight = watchState.preflight
        }
    }

    func stopWatchService() async {
        await runBlockingTask(label: "Stopping watch service") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let watchState = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().watchStop(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.applyLiveSnapshots(watchState: watchState, shots: self.shotsSnapshot)
            self.recordLiveEvent("Watch service stopped")
            self.statusMessage = "Watch service stopped"
        }
    }

    func refreshLiveData(silent: Bool = false) async {
        let repoRoot = self.repoRoot
        let configPath = self.configPath

        if !silent {
            isBusy = true
            errorMessage = nil
            statusMessage = "Refreshing live status"
        }
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                let client = BridgeClient()
                let watchState = try client.watchState(repoRoot: repoRoot, configPath: configPath, limit: 250, tailLines: 60)
                let shots = try client.shotsSummary(repoRoot: repoRoot, configPath: configPath, limit: 500)
                return (watchState, shots)
            }.value
            applyLiveSnapshots(watchState: snapshot.0, shots: snapshot.1)
            watchPreflight = snapshot.0.preflight ?? watchPreflight
            if !silent {
                statusMessage = "Live status updated"
            }
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
                statusMessage = "Error"
            } else {
                recordLiveEvent("Live poll error: \(error.localizedDescription)")
            }
        }
        if !silent {
            isBusy = false
        }
    }

    func setMonitoringEnabled(for section: AppSection?) {
        let liveSections: Set<AppSection> = [.liveMonitor, .queue, .shots]
        if let section, liveSections.contains(section) {
            startMonitoringLoop()
        } else {
            stopMonitoringLoop()
        }
    }

    func refreshLogsDiagnostics(severity: String? = nil) async {
        await runBlockingTask(label: "Refreshing logs and diagnostics") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let snapshot = try await Task.detached(priority: .utility) {
                try BridgeClient().logsDiagnostics(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    severity: severity,
                    limit: 500
                )
            }.value
            self.logsDiagnostics = snapshot
            self.statusMessage = "Logs/diagnostics updated"
        }
    }

    func validateConfig() async {
        await runBlockingTask(label: "Validating config") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let snapshot = try await Task.detached(priority: .utility) {
                try BridgeClient().configValidate(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.configValidation = snapshot
            self.statusMessage = snapshot.ok ? "Config validation passed" : "Config validation failed"
        }
    }

    func refreshWatchPreflight() async {
        await runBlockingTask(label: "Running watch preflight") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let snapshot = try await Task.detached(priority: .utility) {
                try BridgeClient().watchPreflight(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.watchPreflight = snapshot
            self.statusMessage = snapshot.ok ? "Watch preflight passed" : "Watch preflight blocked"
        }
    }

    func refreshHistory() async {
        await runBlockingTask(label: "Refreshing history") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let snapshot = try await Task.detached(priority: .utility) {
                try BridgeClient().historySummary(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    limit: 50,
                    gapMinutes: 30
                )
            }.value
            self.historySummary = snapshot
            self.statusMessage = "History updated"
        }
    }

    func copyDiagnosticsBundle(outDir: String? = nil) async {
        await runBlockingTask(label: "Creating diagnostics bundle") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().copyDiagnosticsBundle(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    outDir: outDir
                )
            }.value
            self.lastDiagnosticsBundlePath = result.bundlePath
            self.statusMessage = "Diagnostics bundle created"
        }
    }

    private func startMonitoringLoop() {
        if monitorTask != nil {
            return
        }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLiveData(silent: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.refreshLiveData(silent: true)
            }
        }
        statusMessage = "Live monitoring enabled"
    }

    private func stopMonitoringLoop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func applyLiveSnapshots(watchState: WatchServiceState, shots: ShotsSummarySnapshot?) {
        watchServiceState = watchState
        queueSnapshot = watchState.queue
        if let shots {
            shotsSnapshot = shots
        }
        let counts = watchState.queue.counts
        if lastQueueCounts != counts {
            let msg = "Queue counts updated: detected \(counts["detected", default: 0]), decoding \(counts["decoding", default: 0]), xform \(counts["xform", default: 0]), dpx_write \(counts["dpx_write", default: 0]), done \(counts["done", default: 0]), failed \(counts["failed", default: 0])"
            recordLiveEvent(msg)
            lastQueueCounts = counts
        }
        if lastWatchRunning != watchState.running {
            recordLiveEvent(watchState.running ? "Watch process is running" : "Watch process is stopped")
            lastWatchRunning = watchState.running
        }
    }

    private func recordLiveEvent(_ message: String) {
        let line = "[\(timestampNow())] \(message)"
        liveEvents.insert(line, at: 0)
        if liveEvents.count > 400 {
            liveEvents = Array(liveEvents.prefix(400))
        }
    }

    private func timestampNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: Date())
    }

    private func runBlockingTask(label: String, work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        statusMessage = label
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error"
        }
        isBusy = false
    }
}
