import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum NotificationKind: String, Sendable {
    case info
    case warning
    case error
}

struct NotificationRecord: Identifiable, Sendable {
    let id = UUID()
    let kind: NotificationKind
    let title: String
    let message: String
    let likelyCause: String?
    let suggestedAction: String?
    let createdAt: Date

    var createdAtLabel: String {
        NotificationRecord.timestampFormatter.string(from: createdAt)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedHub: LifecycleHub = .configure
    @Published var selectedConfigurePanel: ConfigurePanel = .projectSettings
    @Published var selectedTriagePanel: TriagePanel = .shots
    @Published var selectedDeliverPanel: DeliverPanel = .dayWrap
    @Published var repoRoot: String {
        didSet {
            UserDefaults.standard.set(repoRoot, forKey: Self.repoRootDefaultsKey)
        }
    }
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
    @Published var deliveryOperationEnvelope: ToolOperationEnvelope?
    @Published var deliveryOperationRevision: Int = 0
    @Published var deliveryRunState: DeliveryRunState = .idleDefault
    @Published var liveEvents: [String] = []
    @Published var queueDepthTrend: [Int] = []
    @Published var throughputFramesPerMinute: Double = 0.0
    @Published var lastFrameAt: Date?
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    @Published var presentedError: PresentedError?
    @Published var notifications: [NotificationRecord] = []
    @Published var activeToast: NotificationRecord?
    @Published var isNotificationsCenterPresented: Bool = false
    @Published var isBusy: Bool = false
    @Published var workspaceAccessActive: Bool = false
    @Published var reduceMotionEnabled: Bool = false
    @Published var monitoringEnabled: Bool = false
    @Published var monitoringPollInFlight: Bool = false
    @Published var monitoringConsecutiveFailures: Int = 0
    @Published var monitoringPollIntervalSeconds: Double = 1.0
    @Published var monitoringNextPollAt: Date?
    @Published var monitoringLastSuccessAt: Date?
    @Published var monitoringLastFailureAt: Date?
    @Published var monitoringLastFailureMessage: String?

    private var monitorTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var monitorSessionToken = UUID()
    private var liveRefreshInFlight: Bool = false
    private var hasEmittedMonitoringFailureWarning: Bool = false
    private var lastQueueCounts: [String: Int] = [:]
    private var lastWatchRunning: Bool?
    private var lastDoneFrameCountSample: Int?
    private var lastRateSampleAt: Date?
    private var seenDiagnosticWarningKeys: Set<String> = []
    private let maxDeliveryRunEvents: Int = 120
    private static let repoRootDefaultsKey = "stopmo_repo_root"
    private static let workspaceBookmarkDefaultsKey = "stopmo_workspace_bookmark"
    private static let defaultWorkspaceFolderName = "StopmoXcodeWorkspace"
    private var securityScopedWorkspaceURL: URL?
    private let workspaceIO = WorkspaceIOService()

    init() {
        let root = Self.resolveInitialRepoRoot()
        repoRoot = root
        configPath = Self.defaultConfigPath(forWorkspaceRoot: root)
        restoreWorkspaceAccess()
        bootstrapWorkspaceIfNeeded()
    }

    deinit {
        monitorTask?.cancel()
        toastDismissTask?.cancel()
        if let url = securityScopedWorkspaceURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var monitoringBackoffActive: Bool {
        monitoringConsecutiveFailures > 0
    }

    var monitoringStatusLabel: String {
        if monitoringConsecutiveFailures == 0 {
            return monitoringEnabled ? "Healthy" : "Idle"
        }
        if monitoringConsecutiveFailures >= 3 {
            return "Recovery Needed"
        }
        return "Degraded"
    }

    var currentPanelLabel: String {
        switch selectedHub {
        case .configure:
            return selectedConfigurePanel.rawValue
        case .capture:
            return "Live Capture"
        case .triage:
            return selectedTriagePanel.rawValue
        case .deliver:
            return selectedDeliverPanel.rawValue
        }
    }

    var hubPanelContextLabel: String {
        "\(selectedHub.rawValue) / \(currentPanelLabel)"
    }

    func restartMonitoringLoop() {
        stopMonitoringLoop()
        startMonitoringLoop(force: true)
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

    func saveConfig(config overrideConfig: StopmoConfigDocument? = nil) async {
        await runBlockingTask(label: "Saving config") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let payload = overrideConfig ?? self.config
            let saved = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().writeConfig(repoRoot: repoRoot, configPath: configPath, config: payload)
            }.value
            self.config = saved
            self.statusMessage = "Saved config"
        }
    }

    func startWatchService() async {
        let shouldResumeMonitoring = monitorTask != nil
        if shouldResumeMonitoring {
            stopMonitoringLoop()
        }
        await runBlockingTask(label: "Starting watch service") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let watchState = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().watchStart(repoRoot: repoRoot, configPath: configPath)
            }.value
            self.applyLiveSnapshots(watchState: watchState, shots: self.shotsSnapshot)
            if watchState.startBlocked == true {
                self.recordLiveEvent("Watch start blocked by preflight")
                self.presentWarning(
                    title: "Watch Start Blocked",
                    message: "Watch start was blocked by preflight checks.",
                    likelyCause: "Preflight blockers are still present in the current config/runtime.",
                    suggestedAction: "Run Watch Preflight in Configure > Workspace & Health, resolve blockers, then start watch again."
                )
                self.statusMessage = "Watch start blocked"
            } else if let launchError = watchState.launchError, !launchError.isEmpty {
                self.recordLiveEvent("Watch start failed: \(launchError)")
                self.presentWarning(
                    title: "Watch Start Failed",
                    message: launchError,
                    likelyCause: "Watch process launch did not complete successfully.",
                    suggestedAction: "Check Runtime Health and Logs & Diagnostics, then retry Start Watch."
                )
                self.statusMessage = "Watch start failed"
            } else {
                self.recordLiveEvent("Watch service started")
                self.statusMessage = "Watch service running"
            }
            self.watchPreflight = watchState.preflight
        }
        if shouldResumeMonitoring, shouldMonitorCurrentSelection() {
            startMonitoringLoop(force: true)
        }
    }

    func stopWatchService() async {
        let shouldResumeMonitoring = monitorTask != nil
        if shouldResumeMonitoring {
            stopMonitoringLoop()
        }
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
        if shouldResumeMonitoring, shouldMonitorCurrentSelection() {
            startMonitoringLoop(force: true)
        }
    }

    func restartWatchService() async {
        let shouldResumeMonitoring = monitorTask != nil
        if shouldResumeMonitoring {
            stopMonitoringLoop()
        }
        await runBlockingTask(label: "Restarting watch service") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let client = BridgeClient()

            _ = try await Task.detached(priority: .userInitiated) {
                try client.watchStop(repoRoot: repoRoot, configPath: configPath)
            }.value

            let watchState = try await Task.detached(priority: .userInitiated) {
                try client.watchStart(repoRoot: repoRoot, configPath: configPath)
            }.value

            self.applyLiveSnapshots(watchState: watchState, shots: self.shotsSnapshot)
            if watchState.startBlocked == true {
                self.recordLiveEvent("Watch restart blocked by preflight")
                self.presentWarning(
                    title: "Watch Restart Blocked",
                    message: "Watch restart was blocked by preflight checks.",
                    likelyCause: "Preflight blockers are still present in the current config/runtime.",
                    suggestedAction: "Run Watch Preflight in Configure > Workspace & Health, resolve blockers, then retry restart."
                )
                self.statusMessage = "Watch restart blocked"
            } else if let launchError = watchState.launchError, !launchError.isEmpty {
                self.recordLiveEvent("Watch restart failed: \(launchError)")
                self.presentWarning(
                    title: "Watch Restart Failed",
                    message: launchError,
                    likelyCause: "Watch process did not relaunch successfully.",
                    suggestedAction: "Run Runtime Health checks and review watch log tail, then retry."
                )
                self.statusMessage = "Watch restart failed"
            } else {
                self.recordLiveEvent("Watch service restarted")
                self.statusMessage = "Watch service running"
            }
            self.watchPreflight = watchState.preflight
        }
        if shouldResumeMonitoring, shouldMonitorCurrentSelection() {
            startMonitoringLoop(force: true)
        }
    }

    func refreshLiveData(silent: Bool = false) async {
        _ = await refreshLiveDataInternal(
            silent: silent,
            source: .manual,
            expectedSessionToken: monitorSessionToken
        )
    }

    enum RefreshKind: Equatable {
        case health
        case config
        case live
        case logs
        case history
        case dayWrap
    }

    func refreshKindForCurrentSelection() -> RefreshKind {
        switch selectedHub {
        case .configure:
            switch selectedConfigurePanel {
            case .workspaceHealth:
                return .health
            case .projectSettings:
                return .config
            case .calibration:
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

    func refreshCurrentSelection() async {
        switch refreshKindForCurrentSelection() {
        case .health:
            await refreshHealth()
        case .config:
            await loadConfig()
        case .live:
            await refreshLiveData()
        case .logs:
            await refreshLogsDiagnostics()
        case .history:
            await refreshHistory()
        case .dayWrap:
            await loadConfig()
            await refreshLiveData(silent: true)
        }
    }

    func updateMonitoringForSelection() {
        if shouldMonitorCurrentSelection() {
            startMonitoringLoop()
        } else {
            stopMonitoringLoop()
        }
    }

    @discardableResult
    private func refreshLiveDataInternal(
        silent: Bool,
        source: LiveRefreshSource,
        expectedSessionToken: UUID
    ) async -> Bool {
        if source == .monitor, expectedSessionToken != monitorSessionToken {
            return false
        }
        if liveRefreshInFlight {
            if !silent {
                statusMessage = "Live refresh already in progress"
            }
            return true
        }

        let repoRoot = self.repoRoot
        let configPath = self.configPath
        let limits = snapshotFetchLimitsForCurrentSelection()

        liveRefreshInFlight = true
        if source == .monitor {
            monitoringPollInFlight = true
            monitoringEnabled = true
        }
        if !silent {
            isBusy = true
            clearError()
            statusMessage = "Refreshing live status"
        }
        defer {
            liveRefreshInFlight = false
            if source == .monitor {
                monitoringPollInFlight = false
            }
            if !silent {
                isBusy = false
            }
        }

        do {
            let snapshot = try await Task.detached(priority: .utility) {
                let client = BridgeClient()
                let watchState = try client.watchState(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    limit: limits.queueLimit,
                    tailLines: limits.logTailLines
                )
                let shots: ShotsSummarySnapshot? = limits.includeShots
                    ? try client.shotsSummary(repoRoot: repoRoot, configPath: configPath, limit: limits.shotsLimit)
                    : nil
                return (watchState, shots)
            }.value

            if source == .monitor, expectedSessionToken != monitorSessionToken {
                return false
            }

            applyLiveSnapshots(watchState: snapshot.0, shots: snapshot.1)
            watchPreflight = snapshot.0.preflight ?? watchPreflight
            registerMonitoringSuccess(with: snapshot.0)
            if !silent {
                statusMessage = "Live status updated"
            }
        } catch {
            if source == .monitor, expectedSessionToken != monitorSessionToken {
                return false
            }

            registerMonitoringFailure(error.localizedDescription)
            if !silent {
                presentError(title: "Live Refresh Failed", message: error.localizedDescription)
            } else if monitoringConsecutiveFailures == 1 || monitoringConsecutiveFailures % 3 == 0 {
                let delayText = String(format: "%.1f", monitoringPollIntervalSeconds)
                recordLiveEvent("Live poll error: \(error.localizedDescription) (retry in \(delayText)s)")
            }
        }
        return true
    }

    private struct LiveSnapshotFetchLimits {
        let queueLimit: Int
        let logTailLines: Int
        let includeShots: Bool
        let shotsLimit: Int
    }

    private func snapshotFetchLimitsForCurrentSelection() -> LiveSnapshotFetchLimits {
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

    private func registerMonitoringSuccess(with watchState: WatchServiceState) {
        let hadFailures = monitoringConsecutiveFailures > 0
        let reduced = MonitoringReducer.successTransition(watchState: watchState, now: Date())
        monitoringConsecutiveFailures = reduced.consecutiveFailures
        monitoringLastFailureMessage = nil
        monitoringLastSuccessAt = reduced.lastSuccessAt
        monitoringPollIntervalSeconds = reduced.pollIntervalSeconds
        monitoringNextPollAt = nil
        if hadFailures {
            recordLiveEvent("Live polling recovered")
        }
        hasEmittedMonitoringFailureWarning = false
    }

    private func registerMonitoringFailure(_ message: String) {
        let reduced = MonitoringReducer.failureTransition(previousFailures: monitoringConsecutiveFailures, now: Date())
        monitoringConsecutiveFailures = reduced.consecutiveFailures
        monitoringLastFailureAt = Date()
        monitoringLastFailureMessage = message
        monitoringPollIntervalSeconds = reduced.pollIntervalSeconds
        monitoringNextPollAt = reduced.nextPollAt
        if reduced.shouldEmitDegradedWarning, !hasEmittedMonitoringFailureWarning {
            presentWarning(
                title: "Live Monitoring Degraded",
                message: "Polling has failed \(monitoringConsecutiveFailures) times in a row.",
                likelyCause: "Bridge/watch calls are failing or timing out.",
                suggestedAction: "Use Retry/Restart actions in Live Monitor recovery controls."
            )
            hasEmittedMonitoringFailureWarning = true
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
            self.ingestDiagnosticWarnings(snapshot.warnings)
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

    func publishDeliveryOperation(_ envelope: ToolOperationEnvelope) {
        deliveryOperationEnvelope = envelope
        deliveryOperationRevision += 1
    }

    func beginDeliveryRun(kind: DeliveryRunKind, total: Int, label: String) {
        deliveryRunState = DeliveryRunReducer.begin(
            kind: kind,
            total: total,
            label: label,
            nowUtc: Self.timestampUtcNow()
        )
    }

    func appendDeliveryEvent(
        tone: DeliveryRunEventTone,
        title: String,
        detail: String,
        shotName: String? = nil,
        timestampUtc: String? = nil
    ) {
        DeliveryRunReducer.appendEvent(
            state: &deliveryRunState,
            tone: tone,
            title: title,
            detail: detail,
            shotName: shotName,
            timestampUtc: timestampUtc ?? Self.timestampUtcNow(),
            maxEvents: maxDeliveryRunEvents
        )
    }

    func updateDeliveryRunProgress(completed: Int, failed: Int, activeLabel: String) {
        DeliveryRunReducer.updateProgress(
            state: &deliveryRunState,
            completed: completed,
            failed: failed,
            activeLabel: activeLabel
        )
    }

    func finishDeliveryRun(
        status: DeliveryRunStatus,
        outputs: [String],
        completed: Int? = nil,
        total: Int? = nil,
        failed: Int? = nil,
        activeLabel: String? = nil
    ) {
        DeliveryRunReducer.finish(
            state: &deliveryRunState,
            status: status,
            outputs: outputs,
            completed: completed,
            total: total,
            failed: failed,
            activeLabel: activeLabel,
            nowUtc: Self.timestampUtcNow()
        )
    }

    func pruneDeliverySelection(_ selected: Set<String>, from snapshot: ShotsSummarySnapshot?) -> Set<String> {
        DeliveryRunReducer.pruneSelection(selected, snapshot: snapshot)
    }

    func runDayWrapBatchDelivery(
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool
    ) async -> ToolOperationEnvelope? {
        let trimmedInput = inputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            presentWarning(
                title: "Input Directory Required",
                message: "Select a DPX input directory before running Day Wrap delivery.",
                likelyCause: "Day Wrap input path is empty.",
                suggestedAction: "Set input root in Deliver > Day Wrap and retry."
            )
            return nil
        }

        let resolvedOutput = outputDir?.trimmingCharacters(in: .whitespacesAndNewlines)
        let repoRoot = self.repoRoot
        let originalRepoRoot = self.repoRoot
        let originalConfigPath = self.configPath
        isBusy = true
        clearError()
        statusMessage = "Running Day Wrap delivery"
        beginDeliveryRun(kind: .dayWrapBatch, total: 0, label: "Running day wrap batch...")
        appendDeliveryEvent(
            tone: .warning,
            title: "Day Wrap Started",
            detail: "Batch DPX -> ProRes started for \(trimmedInput)."
        )
        defer { isBusy = false }
        defer {
            self.restoreWorkspaceContextIfNeeded(
                expectedRepoRoot: originalRepoRoot,
                expectedConfigPath: originalConfigPath
            )
        }

        do {
            let envelope = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().dpxToProres(
                    repoRoot: repoRoot,
                    inputDir: trimmedInput,
                    outputDir: (resolvedOutput?.isEmpty == false) ? resolvedOutput : nil,
                    framerate: max(1, framerate),
                    overwrite: overwrite
                )
            }.value

            publishDeliveryOperation(envelope)
            let outputs = Self.outputPaths(from: envelope)
            let completed = envelope.operation.result?["count"]?.intValue ?? outputs.count
            let reportedTotal = envelope.operation.result?["total_sequences"]?.intValue ?? max(completed, outputs.count)
            let total = max(reportedTotal, completed, outputs.count)
            let failed = max(0, total - completed)
            updateDeliveryRunProgress(
                completed: completed,
                failed: failed,
                activeLabel: "Day wrap batch complete"
            )
            let runStatus: DeliveryRunStatus = failed > 0 ? .partial : .succeeded
            finishDeliveryRun(
                status: runStatus,
                outputs: outputs,
                completed: completed,
                total: total,
                failed: failed,
                activeLabel: failed > 0 ? "Completed with issues" : "Completed successfully"
            )
            appendDeliveryEvent(
                tone: failed > 0 ? .warning : .success,
                title: failed > 0 ? "Day Wrap Partial" : "Day Wrap Complete",
                detail: "Completed \(completed) / \(total) sequences."
            )
            presentInfo(
                title: "Day Wrap Complete",
                message: "Completed \(completed) / \(total) sequences.",
                likelyCause: nil,
                suggestedAction: "Open output paths below or review full run details in Advanced."
            )
            statusMessage = "Day wrap delivery complete"
            return envelope
        } catch {
            appendDeliveryEvent(
                tone: .danger,
                title: "Day Wrap Failed",
                detail: error.localizedDescription
            )
            finishDeliveryRun(
                status: .failed,
                outputs: [],
                activeLabel: "Day wrap failed"
            )
            presentError(title: "Day Wrap Delivery Failed", message: error.localizedDescription)
            return nil
        }
    }

    func deliverShotsToProres(
        shotInputRoots: [String],
        framerate: Int,
        overwrite: Bool,
        outputDir: String? = nil
    ) async -> [String] {
        var deliveredOutputs: [String] = []
        let originalRepoRoot = self.repoRoot
        let originalConfigPath = self.configPath
        await runBlockingTask(label: "Delivering selected shots") {
            let roots = shotInputRoots
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let uniqueRoots = Array(NSOrderedSet(array: roots)) as? [String] ?? roots
            guard !uniqueRoots.isEmpty else {
                throw BridgeError.processFailed("No completed shots were selected for delivery.")
            }

            let repoRoot = self.repoRoot
            let resolvedOutput = outputDir?.trimmingCharacters(in: .whitespacesAndNewlines)
            var failedShots: [String] = []
            var completedShots = 0
            var failedCount = 0
            self.beginDeliveryRun(kind: .selectedShots, total: uniqueRoots.count, label: "Starting selected delivery...")
            self.appendDeliveryEvent(
                tone: .warning,
                title: "Selected Delivery Started",
                detail: "Processing \(uniqueRoots.count) selected shot(s)."
            )

            for (index, inputRoot) in uniqueRoots.enumerated() {
                let shotLabel = URL(fileURLWithPath: inputRoot).lastPathComponent
                let activeLabel = "Delivering \(index + 1) / \(uniqueRoots.count): \(shotLabel)"
                self.statusMessage = activeLabel
                self.updateDeliveryRunProgress(
                    completed: completedShots,
                    failed: failedCount,
                    activeLabel: activeLabel
                )
                self.appendDeliveryEvent(
                    tone: .neutral,
                    title: "Shot Started",
                    detail: activeLabel,
                    shotName: shotLabel
                )
                do {
                    let envelope = try await Task.detached(priority: .userInitiated) {
                        try BridgeClient().dpxToProres(
                            repoRoot: repoRoot,
                            inputDir: inputRoot,
                            outputDir: resolvedOutput?.isEmpty == false ? resolvedOutput : nil,
                            framerate: max(1, framerate),
                            overwrite: overwrite
                        )
                    }.value
                    self.publishDeliveryOperation(envelope)
                    let outputs = Self.outputPaths(from: envelope)
                    if outputs.isEmpty {
                        failedShots.append("\(shotLabel): no ProRes outputs were generated")
                        failedCount += 1
                        self.appendDeliveryEvent(
                            tone: .danger,
                            title: "Shot Failed",
                            detail: "No ProRes outputs were generated.",
                            shotName: shotLabel
                        )
                    } else {
                        deliveredOutputs.append(contentsOf: outputs)
                        completedShots += 1
                        self.appendDeliveryEvent(
                            tone: .success,
                            title: "Shot Delivered",
                            detail: "Generated \(outputs.count) output clip(s).",
                            shotName: shotLabel
                        )
                    }
                } catch {
                    failedShots.append("\(shotLabel): \(error.localizedDescription)")
                    failedCount += 1
                    self.appendDeliveryEvent(
                        tone: .danger,
                        title: "Shot Failed",
                        detail: error.localizedDescription,
                        shotName: shotLabel
                    )
                }
                self.updateDeliveryRunProgress(
                    completed: completedShots,
                    failed: failedCount,
                    activeLabel: "Processed \(completedShots + failedCount) / \(uniqueRoots.count)"
                )
            }

            if deliveredOutputs.isEmpty {
                let detail = failedShots.joined(separator: "\n")
                self.finishDeliveryRun(
                    status: .failed,
                    outputs: [],
                    completed: completedShots,
                    total: uniqueRoots.count,
                    failed: failedCount,
                    activeLabel: "Selected delivery failed"
                )
                self.appendDeliveryEvent(
                    tone: .danger,
                    title: "Selected Delivery Failed",
                    detail: "No ProRes outputs were generated."
                )
                throw BridgeError.processFailed(
                    detail.isEmpty
                        ? "No ProRes outputs were generated from the selected shots."
                        : detail
                )
            }

            let runStatus: DeliveryRunStatus = failedCount > 0 ? .partial : .succeeded
            self.finishDeliveryRun(
                status: runStatus,
                outputs: deliveredOutputs,
                completed: completedShots,
                total: uniqueRoots.count,
                failed: failedCount,
                activeLabel: failedCount > 0 ? "Completed with some failures" : "Completed successfully"
            )
            self.appendDeliveryEvent(
                tone: failedCount > 0 ? .warning : .success,
                title: failedCount > 0 ? "Selected Delivery Partial" : "Selected Delivery Complete",
                detail: "Delivered \(deliveredOutputs.count) clip(s) from \(completedShots) shot(s)."
            )

            if !failedShots.isEmpty {
                self.presentWarning(
                    title: "Partial Shot Delivery",
                    message: "Delivered \(deliveredOutputs.count) ProRes clip(s); \(failedShots.count) shot(s) failed.",
                    likelyCause: "Some selected shots are missing DPX frames or have output naming/path conflicts.",
                    suggestedAction: "Inspect failed shot folders in Triage > Shots, then retry failed shots or run Deliver > Day Wrap."
                )
            } else {
                self.presentInfo(
                    title: "Shot Delivery Complete",
                    message: "Delivered \(deliveredOutputs.count) ProRes clip(s) from \(uniqueRoots.count) shot(s).",
                    likelyCause: nil,
                    suggestedAction: "Open outputs from Triage > Shots or review runs in Deliver > Run History."
                )
            }
            self.statusMessage = "Shot delivery complete"
        }
        restoreWorkspaceContextIfNeeded(
            expectedRepoRoot: originalRepoRoot,
            expectedConfigPath: originalConfigPath
        )
        return deliveredOutputs
    }

    private func restoreWorkspaceContextIfNeeded(expectedRepoRoot: String, expectedConfigPath: String) {
        guard repoRoot != expectedRepoRoot || configPath != expectedConfigPath else {
            return
        }

        let expectedConfigExists = FileManager.default.fileExists(atPath: expectedConfigPath)
        guard expectedConfigExists else {
            return
        }

        let currentConfig = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentDefaultConfig = Self.defaultConfigPath(forWorkspaceRoot: repoRoot)
        let currentConfigLooksAutoDefault = currentConfig == currentDefaultConfig
        let currentConfigExists = FileManager.default.fileExists(atPath: currentConfig)
        guard currentConfigLooksAutoDefault, !currentConfigExists else {
            return
        }

        repoRoot = expectedRepoRoot
        configPath = expectedConfigPath
        appendDeliveryEvent(
            tone: .warning,
            title: "Workspace Restored",
            detail: "Restored workspace/config context after delivery path mutation was detected."
        )
        statusMessage = "Workspace context restored"
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
            self.presentInfo(
                title: "Diagnostics Bundle Created",
                message: result.bundlePath,
                likelyCause: nil,
                suggestedAction: "Share this bundle with support or attach it to issue reports."
            )
            self.statusMessage = "Diagnostics bundle created"
        }
    }

    func retryFailedQueueJobs(jobIds: [Int]? = nil) async {
        await runBlockingTask(label: "Retrying failed queue jobs") {
            let repoRoot = self.repoRoot
            let configPath = self.configPath
            let retryIds = jobIds
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().queueRetryFailed(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    jobIds: retryIds
                )
            }.value
            self.queueSnapshot = result.queue
            if var watch = self.watchServiceState {
                watch.queue = result.queue
                self.watchServiceState = watch
            }
            if result.retried > 0 {
                self.presentInfo(
                    title: "Queue Jobs Retried",
                    message: "Reset \(result.retried) failed job(s) to detected.",
                    likelyCause: nil,
                    suggestedAction: "Monitor Live Monitor/Queue to confirm jobs progress through stages."
                )
            } else {
                self.presentWarning(
                    title: "No Failed Jobs Retried",
                    message: "No failed jobs matched the selected retry criteria.",
                    likelyCause: "There are no failed jobs or selected IDs are not currently failed.",
                    suggestedAction: "Refresh Queue and verify failed rows before retrying."
                )
            }
            self.statusMessage = "Retried \(result.retried) failed job(s)"
        }
    }

    func exportQueueSnapshot() {
        guard let snapshot = queueSnapshot else {
            presentWarning(
                title: "Export Queue Snapshot",
                message: "No queue snapshot is currently loaded.",
                likelyCause: "Queue view has not been refreshed yet.",
                suggestedAction: "Refresh queue data, then export snapshot again."
            )
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "queue_snapshot.json"
        panel.title = "Export Queue Snapshot"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            presentInfo(
                title: "Queue Snapshot Exported",
                message: url.path,
                likelyCause: nil,
                suggestedAction: "Use this JSON snapshot for debugging or support triage."
            )
            statusMessage = "Queue snapshot exported"
        } catch {
            presentError(title: "Queue Export Failed", message: error.localizedDescription)
        }
    }

    private enum LiveRefreshSource {
        case manual
        case monitor
    }

    private static func outputPaths(from envelope: ToolOperationEnvelope) -> [String] {
        envelope.operation.result?["outputs"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private static func timestampUtcNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    func shouldMonitorCurrentSelection() -> Bool {
        switch selectedHub {
        case .capture:
            return true
        case .triage:
            return selectedTriagePanel == .shots || selectedTriagePanel == .queue
        case .configure, .deliver:
            return false
        }
    }

    private func startMonitoringLoop(force: Bool = false) {
        if monitorTask != nil, !force {
            return
        }
        stopMonitoringLoop()
        monitorSessionToken = UUID()
        let sessionToken = monitorSessionToken
        monitoringEnabled = true
        monitoringPollIntervalSeconds = 1.0
        monitoringConsecutiveFailures = 0
        monitoringNextPollAt = nil
        monitoringLastFailureMessage = nil
        hasEmittedMonitoringFailureWarning = false

        monitorTask = Task { [weak self] in
            guard let self else { return }
            let firstPass = await self.refreshLiveDataInternal(
                silent: true,
                source: .monitor,
                expectedSessionToken: sessionToken
            )
            if !firstPass {
                return
            }
            while !Task.isCancelled {
                if sessionToken != self.monitorSessionToken {
                    break
                }
                let interval = max(0.5, self.monitoringPollIntervalSeconds)
                self.monitoringNextPollAt = Date().addingTimeInterval(interval)
                let nanos = UInt64(interval * 1_000_000_000.0)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    break
                }
                if Task.isCancelled || sessionToken != self.monitorSessionToken {
                    break
                }
                let shouldContinue = await self.refreshLiveDataInternal(
                    silent: true,
                    source: .monitor,
                    expectedSessionToken: sessionToken
                )
                if !shouldContinue {
                    break
                }
            }
        }
        statusMessage = "Live monitoring enabled"
    }

    private func stopMonitoringLoop() {
        monitorTask?.cancel()
        monitorTask = nil
        monitorSessionToken = UUID()
        monitoringEnabled = false
        monitoringPollInFlight = false
        monitoringNextPollAt = nil
    }

    private func applyLiveSnapshots(watchState: WatchServiceState, shots: ShotsSummarySnapshot?) {
        watchServiceState = watchState
        queueSnapshot = watchState.queue
        if let shots {
            shotsSnapshot = shots
        }
        let counts = watchState.queue.counts

        updateLiveTelemetry(with: watchState, counts: counts)

        let previousFailed = lastQueueCounts["failed", default: 0]
        let currentFailed = counts["failed", default: 0]
        if currentFailed > previousFailed {
            presentWarning(
                title: "Queue Failures Detected",
                message: "\(currentFailed) job(s) are currently in failed state.",
                likelyCause: "At least one frame failed during decode/xform/write stages.",
                suggestedAction: "Open Queue to inspect `last error` values and retry failed jobs."
            )
        }
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

    private func updateLiveTelemetry(with watchState: WatchServiceState, counts: [String: Int]) {
        let reduced = LiveTelemetryReducer.updateTelemetry(
            watchState: watchState,
            counts: counts,
            previousDoneFrameCount: lastDoneFrameCountSample,
            previousSampleAt: lastRateSampleAt,
            previousLastFrameAt: lastFrameAt,
            previousThroughput: throughputFramesPerMinute,
            previousQueueDepthTrend: queueDepthTrend,
            now: Date()
        )
        throughputFramesPerMinute = reduced.throughputFramesPerMinute
        lastFrameAt = reduced.lastFrameAt
        lastDoneFrameCountSample = reduced.lastDoneFrameCountSample
        lastRateSampleAt = reduced.lastRateSampleAt
        queueDepthTrend = reduced.queueDepthTrend
    }

    private func recordLiveEvent(_ message: String) {
        liveEvents = LiveTelemetryReducer.recordLiveEvent(
            existingEvents: liveEvents,
            message: message,
            timestamp: timestampNow(),
            maxEvents: 400
        )
    }

    private func timestampNow() -> String {
        PathTimestampHelpers.nowTimeLabel()
    }

    private func runBlockingTask(label: String, work: @escaping () async throws -> Void) async {
        isBusy = true
        clearError()
        statusMessage = label
        do {
            try await work()
        } catch {
            presentError(title: "\(label) Failed", message: error.localizedDescription)
        }
        isBusy = false
    }

    func chooseWorkspaceDirectory() {
        guard let selectedURL = workspaceIO.chooseWorkspaceDirectory(initialPath: repoRoot) else {
            return
        }
        do {
            if let current = securityScopedWorkspaceURL {
                workspaceIO.stopAccessingSecurityScope(current)
                securityScopedWorkspaceURL = nil
            }
            let bookmark = try workspaceIO.createSecurityScopedBookmark(for: selectedURL)
            UserDefaults.standard.set(bookmark, forKey: Self.workspaceBookmarkDefaultsKey)
            let started = workspaceIO.startAccessingSecurityScope(selectedURL)
            securityScopedWorkspaceURL = selectedURL
            workspaceAccessActive = started
            repoRoot = selectedURL.path
            configPath = Self.defaultConfigPath(forWorkspaceRoot: selectedURL.path)
            bootstrapWorkspaceIfNeeded()
            statusMessage = started ? "Workspace access granted" : "Workspace selected"
        } catch {
            presentError(title: "Workspace Selection Failed", message: error.localizedDescription)
        }
    }

    func chooseRepoRootDirectory() {
        guard let selectedURL = workspaceIO.chooseRepoRootDirectory(initialPath: repoRoot) else {
            return
        }
        repoRoot = selectedURL.path
        let defaultConfig = Self.defaultConfigPath(forWorkspaceRoot: selectedURL.path)
        if FileManager.default.fileExists(atPath: defaultConfig) {
            configPath = defaultConfig
        } else {
            configPath = defaultConfig
            bootstrapWorkspaceIfNeeded()
        }
        statusMessage = "Workspace root updated"
    }

    func chooseConfigFile() {
        guard let selectedURL = workspaceIO.chooseConfigFile(initialPath: repoRoot) else {
            return
        }
        configPath = selectedURL.path
        statusMessage = "Config path updated"
    }

    var sampleConfigPath: String {
        if let bundledSample = bundledSampleConfigPath() {
            return bundledSample
        }
        return Self.defaultConfigPath(forWorkspaceRoot: repoRoot)
    }

    func useSampleConfig() {
        if !Self.isLikelyRepoRoot(Path: repoRoot) {
            configPath = Self.defaultConfigPath(forWorkspaceRoot: repoRoot)
            if !FileManager.default.fileExists(atPath: configPath) {
                bootstrapWorkspaceIfNeeded()
            }
            statusMessage = "Using workspace default config path"
            return
        }
        guard let sample = resolvedSampleConfigSourcePath() else {
            presentError(
                title: "Sample Config Missing",
                message: "Could not find a sample config source."
            )
            return
        }
        guard FileManager.default.fileExists(atPath: sample) else {
            presentError(
                title: "Sample Config Missing",
                message: "Could not find sample config at \(sample)"
            )
            return
        }
        configPath = sample
        statusMessage = "Using sample config path"
    }

    func createConfigFromSample() {
        let destination = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            presentError(title: "Create Config Failed", message: "Config path is empty.")
            return
        }
        let fm = FileManager.default
        let sample = resolvedSampleConfigSourcePath()
        let canCopySample = sample != nil && fm.fileExists(atPath: sample ?? "")
        if Self.isLikelyRepoRoot(Path: repoRoot), !canCopySample {
            presentError(
                title: "Sample Config Missing",
                message: "Could not find a sample config source."
            )
            return
        }
        if fm.fileExists(atPath: destination) {
            presentInfo(
                title: "Config Already Exists",
                message: destination,
                likelyCause: "A config file is already present at the selected config path.",
                suggestedAction: "Use Load Config to read the file or choose another config path."
            )
            return
        }
        do {
            let parent = (destination as NSString).deletingLastPathComponent
            if !parent.isEmpty, !fm.fileExists(atPath: parent) {
                try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            if Self.isLikelyRepoRoot(Path: repoRoot) {
                try fm.copyItem(atPath: sample ?? "", toPath: destination)
            } else {
                try Self.writeDefaultConfigTemplate(destination: destination, workspaceRoot: repoRoot)
            }
            presentInfo(
                title: "Config Created",
                message: destination,
                likelyCause: nil,
                suggestedAction: "Load the config, edit project values, then save."
            )
            statusMessage = "Config created from sample"
        } catch {
            presentError(title: "Create Config Failed", message: error.localizedDescription)
        }
    }

    func openConfigInFinder() {
        let fm = FileManager.default
        let configURL = URL(fileURLWithPath: configPath)
        if fm.fileExists(atPath: configURL.path) {
            _ = workspaceIO.openPathInFinder(configURL.path)
            statusMessage = "Opened config in Finder"
            return
        }
        let parent = configURL.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.path) {
            workspaceIO.openDirectory(parent.path)
            presentWarning(
                title: "Config File Missing",
                message: "Opened config directory because the target file was not found.",
                likelyCause: "The configured config path does not exist yet.",
                suggestedAction: "Create a config from sample or choose an existing config file."
            )
            return
        }
        presentError(
            title: "Open in Finder Failed",
            message: "Config path not found: \(configPath)"
        )
    }

    func openPathInFinder(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentWarning(
                title: "Open in Finder",
                message: "No path provided.",
                likelyCause: "Selected row has an empty path field.",
                suggestedAction: "Select a row with a valid path and retry."
            )
            return
        }
        switch workspaceIO.openPathInFinder(trimmed) {
        case .openedTarget:
            statusMessage = "Opened in Finder"
        case .openedParent:
            presentWarning(
                title: "Path Missing",
                message: "Opened parent folder because target path was not found.",
                likelyCause: "The referenced output/source path does not exist yet.",
                suggestedAction: "Verify pipeline outputs or refresh live state."
            )
        case .missing:
            presentError(title: "Open in Finder Failed", message: "Path not found: \(trimmed)")
        }
    }

    func copyTextToPasteboard(_ text: String, label: String = "Text") {
        workspaceIO.copyToPasteboard(text)
        statusMessage = "Copied \(label)"
    }

    private func bootstrapWorkspaceIfNeeded() {
        let workspaceRoot = repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceRoot.isEmpty else {
            return
        }
        let fm = FileManager.default

        do {
            if !fm.fileExists(atPath: workspaceRoot) {
                try fm.createDirectory(atPath: workspaceRoot, withIntermediateDirectories: true)
            }

            let configDestination = configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultConfigPath(forWorkspaceRoot: workspaceRoot)
                : configPath
            configPath = configDestination

            if fm.fileExists(atPath: configDestination) {
                return
            }

            let configParent = (configDestination as NSString).deletingLastPathComponent
            if !configParent.isEmpty, !fm.fileExists(atPath: configParent) {
                try fm.createDirectory(atPath: configParent, withIntermediateDirectories: true)
            }

            try Self.writeDefaultConfigTemplate(destination: configDestination, workspaceRoot: workspaceRoot)
            statusMessage = "Workspace bootstrapped"
        } catch {
            statusMessage = "Workspace bootstrap skipped: \(error.localizedDescription)"
        }
    }

    private func bundledSampleConfigPath() -> String? {
        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent("backend/defaults/sample.yaml").path {
            candidates.append(resourcePath)
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend/defaults/sample.yaml").path)
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func resolvedSampleConfigSourcePath() -> String? {
        let envRepo = ProcessInfo.processInfo.environment["STOPMO_XCODE_ROOT"] ?? ""
        var candidates: [String] = [
            "\(repoRoot)/config/sample.yaml",
            "\(envRepo)/config/sample.yaml",
        ]
        if let bundled = bundledSampleConfigPath() {
            candidates.append(bundled)
        }
        if let discovered = Self.discoverRepoRootNear(path: FileManager.default.currentDirectoryPath) {
            candidates.append("\(discovered)/config/sample.yaml")
        }
        for candidate in candidates.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard !candidate.isEmpty else { continue }
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func defaultConfigPath(forWorkspaceRoot root: String) -> String {
        "\(root)/config/sample.yaml"
    }

    private static func defaultWorkspaceRoot() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent(defaultWorkspaceFolderName)
            .path
    }

    private static func yamlQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func writeDefaultConfigTemplate(destination: String, workspaceRoot: String) throws {
        let incoming = "\(workspaceRoot)/incoming"
        let working = "\(workspaceRoot)/work"
        let output = "\(workspaceRoot)/output"
        let dbPath = "\(working)/queue.sqlite3"
        let logPath = "\(working)/stopmo-xcode.log"

        let directories = [incoming, working, output, "\(workspaceRoot)/config"]
        let fm = FileManager.default
        for dir in directories where !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let yaml = """
        watch:
          source_dir: \(yamlQuote(incoming))
          working_dir: \(yamlQuote(working))
          output_dir: \(yamlQuote(output))
          db_path: \(yamlQuote(dbPath))
          include_extensions:
          - .cr2
          - .cr3
          - .raw
          stable_seconds: 3.0
          poll_interval_seconds: 1.0
          scan_interval_seconds: 5.0
          max_workers: 2
          shot_complete_seconds: 30.0
          shot_regex: null
        pipeline:
          camera_to_reference_matrix:
          - - 1.0
            - 0.0
            - 0.0
          - - 0.0
            - 1.0
            - 0.0
          - - 0.0
            - 0.0
            - 1.0
          exposure_offset_stops: 2.0
          auto_exposure_from_iso: false
          auto_exposure_from_shutter: false
          target_shutter_s: null
          auto_exposure_from_aperture: false
          target_aperture_f: null
          contrast: 1.25
          contrast_pivot_linear: 0.18
          lock_wb_from_first_frame: true
          target_ei: 800
          apply_match_lut: false
          match_lut_path: null
          use_ocio: false
          ocio_config_path: null
          ocio_input_space: camera_linear
          ocio_reference_space: ACES2065-1
          ocio_output_space: ARRI_LogC3_EI800_AWG
        output:
          emit_per_frame_json: true
          emit_truth_frame_pack: true
          truth_frame_index: 1
          write_debug_tiff: false
          write_prores_on_shot_complete: false
          framerate: 24
          show_lut_rec709_path: null
        log_level: INFO
        log_file: \(yamlQuote(logPath))
        """
        try yaml.appending("\n").write(toFile: destination, atomically: true, encoding: .utf8)
    }

    private func restoreWorkspaceAccess() {
        guard let data = UserDefaults.standard.data(forKey: Self.workspaceBookmarkDefaultsKey) else {
            workspaceAccessActive = false
            return
        }
        do {
            let resolved = try workspaceIO.resolveWorkspaceBookmark(data)
            if let refreshed = resolved.refreshedBookmarkData {
                UserDefaults.standard.set(refreshed, forKey: Self.workspaceBookmarkDefaultsKey)
            }
            let started = workspaceIO.startAccessingSecurityScope(resolved.url)
            securityScopedWorkspaceURL = resolved.url
            workspaceAccessActive = started
            if started {
                repoRoot = resolved.url.path
                configPath = Self.defaultConfigPath(forWorkspaceRoot: resolved.url.path)
                bootstrapWorkspaceIfNeeded()
            }
        } catch {
            workspaceAccessActive = false
        }
    }

    private static func resolveInitialRepoRoot() -> String {
        let env = ProcessInfo.processInfo.environment
        if let workspaceRoot = env["STOPMO_XCODE_WORKSPACE_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspaceRoot.isEmpty {
            return workspaceRoot
        }
        for key in ["STOPMO_XCODE_ROOT", "SRCROOT", "PROJECT_DIR"] {
            let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                if let resolved = resolveCandidateRoot(value) {
                    return resolved
                }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: value, isDirectory: &isDir), isDir.boolValue {
                    return value
                }
            }
        }
        if let remembered = UserDefaults.standard.string(forKey: repoRootDefaultsKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: remembered, isDirectory: &isDir), isDir.boolValue {
                return remembered
            }
        }
        if let fromBundle = discoverRepoRootNear(path: Bundle.main.bundleURL.path) {
            return fromBundle
        }
        if let fromCwd = discoverRepoRootNear(path: FileManager.default.currentDirectoryPath) {
            return fromCwd
        }
        return defaultWorkspaceRoot()
    }

    private static func resolveCandidateRoot(_ value: String) -> String? {
        if isLikelyRepoRoot(Path: value) {
            return value
        }
        let url = URL(fileURLWithPath: value).standardizedFileURL
        if url.lastPathComponent == "StopmoXcodeGUI" {
            let parent = url.deletingLastPathComponent().deletingLastPathComponent()
            if isLikelyRepoRoot(Path: parent.path) {
                return parent.path
            }
        }
        return discoverRepoRootNear(path: value)
    }

    private static func discoverRepoRootNear(path: String) -> String? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        if !url.hasDirectoryPath {
            url.deleteLastPathComponent()
        }
        for _ in 0..<10 {
            let candidate = url.path
            if isLikelyRepoRoot(Path: candidate) {
                return candidate
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                break
            }
            url = parent
        }
        return nil
    }

    private static func isLikelyRepoRoot(Path root: String) -> Bool {
        let fm = FileManager.default
        let pyproject = (root as NSString).appendingPathComponent("pyproject.toml")
        let moduleDir = (root as NSString).appendingPathComponent("src/stopmo_xcode")
        return fm.fileExists(atPath: pyproject) && fm.fileExists(atPath: moduleDir)
    }

    func clearError() {
        errorMessage = nil
        presentedError = nil
    }

    func clearNotifications() {
        notifications = []
        statusMessage = "Notifications cleared"
    }

    func toggleNotificationsCenter() {
        isNotificationsCenterPresented.toggle()
    }

    func dismissNotificationsCenter() {
        isNotificationsCenterPresented = false
    }

    var notificationsBadgeText: String? {
        NotificationReducer.badgeText(for: notifications)
    }

    var notificationsBadgeTone: StatusTone {
        NotificationReducer.badgeTone(for: notifications)
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        activeToast = nil
    }

    func copyNotificationToPasteboard(_ notification: NotificationRecord) {
        var lines: [String] = []
        lines.append("[\(notification.kind.rawValue.uppercased())] \(notification.title)")
        lines.append(notification.message)
        if let cause = notification.likelyCause, !cause.isEmpty {
            lines.append("Likely cause: \(cause)")
        }
        if let action = notification.suggestedAction, !action.isEmpty {
            lines.append("Suggested action: \(action)")
        }
        lines.append("Timestamp: \(notification.createdAtLabel)")
        workspaceIO.copyToPasteboard(lines.joined(separator: "\n"))
        statusMessage = "Notification copied"
    }

    func presentWarning(
        title: String,
        message: String,
        likelyCause: String? = nil,
        suggestedAction: String? = nil
    ) {
        postNotification(
            kind: .warning,
            title: title,
            message: message,
            likelyCause: likelyCause,
            suggestedAction: suggestedAction,
            showToast: true
        )
    }

    func presentInfo(
        title: String,
        message: String,
        likelyCause: String? = nil,
        suggestedAction: String? = nil
    ) {
        postNotification(
            kind: .info,
            title: title,
            message: message,
            likelyCause: likelyCause,
            suggestedAction: suggestedAction,
            showToast: true
        )
    }

    func presentError(title: String = "Error", message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let hints = NotificationReducer.errorHints(
            for: trimmed,
            bundledRuntime: health?.backendMode?.lowercased() == "bundled"
        )
        var alertMessage = trimmed
        if let cause = hints.likelyCause {
            alertMessage += "\n\nLikely cause: \(cause)"
        }
        if let action = hints.suggestedAction {
            alertMessage += "\nSuggested action: \(action)"
        }
        errorMessage = trimmed
        presentedError = PresentedError(title: title, message: alertMessage)
        postNotification(
            kind: .error,
            title: title,
            message: trimmed,
            likelyCause: hints.likelyCause,
            suggestedAction: hints.suggestedAction,
            showToast: false
        )
        statusMessage = "Error"
    }

    private func postNotification(
        kind: NotificationKind,
        title: String,
        message: String,
        likelyCause: String?,
        suggestedAction: String?,
        showToast: Bool
    ) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return
        }
        let notification = NotificationRecord(
            kind: kind,
            title: title,
            message: trimmedMessage,
            likelyCause: likelyCause,
            suggestedAction: suggestedAction,
            createdAt: Date()
        )
        NotificationReducer.append(notification, to: &notifications, maxCount: 200)
        if showToast {
            showToastNotification(notification)
        }
    }

    private func showToastNotification(_ notification: NotificationRecord) {
        toastDismissTask?.cancel()
        if reduceMotionEnabled {
            activeToast = notification
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                activeToast = notification
            }
        }
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            await MainActor.run {
                guard self.activeToast?.id == notification.id else {
                    return
                }
                if self.reduceMotionEnabled {
                    self.activeToast = nil
                } else {
                    withAnimation(.easeIn(duration: 0.2)) {
                        self.activeToast = nil
                    }
                }
                self.toastDismissTask = nil
            }
        }
    }

    private func ingestDiagnosticWarnings(_ warnings: [DiagnosticWarningRecord]) {
        var emittedToast = false
        for warning in warnings {
            let key = "\(warning.code)|\(warning.logger ?? "")|\(warning.message)"
            guard !seenDiagnosticWarningKeys.contains(key) else {
                continue
            }
            seenDiagnosticWarningKeys.insert(key)

            let severity = warning.severity.uppercased()
            let isError = severity == "ERROR" || severity == "CRITICAL"
            let kind: NotificationKind = isError ? .error : .warning
            let toast = !emittedToast
            postNotification(
                kind: kind,
                title: "Diagnostic \(warning.code)",
                message: warning.message,
                likelyCause: warning.logger.map { "Reported by \($0)." },
                suggestedAction: "Open Logs & Diagnostics for full structured context and remediation.",
                showToast: toast
            )
            if toast {
                emittedToast = true
            }
        }
    }

}
