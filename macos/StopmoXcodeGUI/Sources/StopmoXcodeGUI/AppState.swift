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
    @Published var selectedSection: AppSection = .setup
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
    @Published var liveEvents: [String] = []
    @Published var queueDepthTrend: [Int] = []
    @Published var throughputFramesPerMinute: Double = 0.0
    @Published var lastFrameAt: Date?
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    @Published var presentedError: PresentedError?
    @Published var notifications: [NotificationRecord] = []
    @Published var activeToast: NotificationRecord?
    @Published var isBusy: Bool = false
    @Published var workspaceAccessActive: Bool = false

    private var monitorTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var lastQueueCounts: [String: Int] = [:]
    private var lastWatchRunning: Bool?
    private var lastDoneFrameCountSample: Int?
    private var lastRateSampleAt: Date?
    private var seenDiagnosticWarningKeys: Set<String> = []
    private static let repoRootDefaultsKey = "stopmo_repo_root"
    private static let workspaceBookmarkDefaultsKey = "stopmo_workspace_bookmark"
    private var securityScopedWorkspaceURL: URL?

    init() {
        let root = Self.resolveInitialRepoRoot()
        repoRoot = root
        configPath = "\(root)/config/sample.yaml"
        restoreWorkspaceAccess()
    }

    deinit {
        monitorTask?.cancel()
        toastDismissTask?.cancel()
        if let url = securityScopedWorkspaceURL {
            url.stopAccessingSecurityScopedResource()
        }
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
                self.presentWarning(
                    title: "Watch Start Blocked",
                    message: "Watch start was blocked by preflight checks.",
                    likelyCause: "Preflight blockers are still present in the current config/runtime.",
                    suggestedAction: "Run Watch Preflight in Setup and resolve all blockers, then start watch again."
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
            clearError()
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
                presentError(title: "Live Refresh Failed", message: error.localizedDescription)
            } else {
                recordLiveEvent("Live poll error: \(error.localizedDescription)")
            }
        }
        if !silent {
            isBusy = false
        }
    }

    func setMonitoringEnabled(for section: AppSection) {
        let liveSections: Set<AppSection> = [.liveMonitor, .queue, .shots]
        if liveSections.contains(section) {
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
        let now = Date()
        let doneCount = counts["done", default: watchState.completedFrames]
        if let prevDone = lastDoneFrameCountSample,
           let prevAt = lastRateSampleAt
        {
            let deltaDone = max(0, doneCount - prevDone)
            let deltaSeconds = now.timeIntervalSince(prevAt)
            if deltaSeconds > 0.05 {
                throughputFramesPerMinute = (Double(deltaDone) / deltaSeconds) * 60.0
            }
            if deltaDone > 0 {
                lastFrameAt = now
            }
        } else if doneCount > 0 {
            lastFrameAt = now
            throughputFramesPerMinute = 0.0
        }

        lastDoneFrameCountSample = doneCount
        lastRateSampleAt = now

        let depth = counts["detected", default: 0]
            + counts["decoding", default: 0]
            + counts["xform", default: 0]
            + counts["dpx_write", default: 0]
        queueDepthTrend.append(depth)
        if queueDepthTrend.count > 180 {
            queueDepthTrend = Array(queueDepthTrend.suffix(180))
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Use Workspace"
        panel.directoryURL = URL(fileURLWithPath: repoRoot, isDirectory: true)
        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            return
        }
        do {
            if let current = securityScopedWorkspaceURL {
                current.stopAccessingSecurityScopedResource()
                securityScopedWorkspaceURL = nil
            }
            let bookmark = try selectedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.workspaceBookmarkDefaultsKey)
            let started = selectedURL.startAccessingSecurityScopedResource()
            securityScopedWorkspaceURL = selectedURL
            workspaceAccessActive = started
            repoRoot = selectedURL.path
            configPath = "\(selectedURL.path)/config/sample.yaml"
            statusMessage = started ? "Workspace access granted" : "Workspace selected"
        } catch {
            presentError(title: "Workspace Selection Failed", message: error.localizedDescription)
        }
    }

    func chooseRepoRootDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Repo Root"
        panel.directoryURL = URL(fileURLWithPath: repoRoot, isDirectory: true)
        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            return
        }
        repoRoot = selectedURL.path
        let defaultConfig = selectedURL.appendingPathComponent("config/sample.yaml").path
        if FileManager.default.fileExists(atPath: defaultConfig) {
            configPath = defaultConfig
        }
        statusMessage = "Repo root updated"
    }

    func chooseConfigFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yaml") ?? .text,
            UTType(filenameExtension: "yml") ?? .text,
        ]
        panel.prompt = "Select Config"
        panel.directoryURL = URL(fileURLWithPath: repoRoot, isDirectory: true)
        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            return
        }
        configPath = selectedURL.path
        statusMessage = "Config path updated"
    }

    var sampleConfigPath: String {
        "\(repoRoot)/config/sample.yaml"
    }

    func useSampleConfig() {
        let sample = sampleConfigPath
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
        let sample = sampleConfigPath
        let destination = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            presentError(title: "Create Config Failed", message: "Config path is empty.")
            return
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: sample) else {
            presentError(
                title: "Sample Config Missing",
                message: "Could not find sample config at \(sample)"
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
            try fm.copyItem(atPath: sample, toPath: destination)
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
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
            statusMessage = "Opened config in Finder"
            return
        }
        let parent = configURL.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
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
        let fm = FileManager.default
        let url = URL(fileURLWithPath: trimmed)
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusMessage = "Opened in Finder"
            return
        }
        let parent = url.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            presentWarning(
                title: "Path Missing",
                message: "Opened parent folder because target path was not found.",
                likelyCause: "The referenced output/source path does not exist yet.",
                suggestedAction: "Verify pipeline outputs or refresh live state."
            )
            return
        }
        presentError(title: "Open in Finder Failed", message: "Path not found: \(trimmed)")
    }

    func copyTextToPasteboard(_ text: String, label: String = "Text") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Copied \(label)"
    }

    private func restoreWorkspaceAccess() {
        guard let data = UserDefaults.standard.data(forKey: Self.workspaceBookmarkDefaultsKey) else {
            workspaceAccessActive = false
            return
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                let refreshed = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: Self.workspaceBookmarkDefaultsKey)
            }
            let started = url.startAccessingSecurityScopedResource()
            securityScopedWorkspaceURL = url
            workspaceAccessActive = started
            if started, Self.isLikelyRepoRoot(Path: url.path) {
                repoRoot = url.path
                configPath = "\(url.path)/config/sample.yaml"
            }
        } catch {
            workspaceAccessActive = false
        }
    }

    private static func resolveInitialRepoRoot() -> String {
        let env = ProcessInfo.processInfo.environment
        for key in ["STOPMO_XCODE_ROOT", "SRCROOT", "PROJECT_DIR"] {
            let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                if let resolved = resolveCandidateRoot(value) {
                    return resolved
                }
            }
        }
        if let remembered = UserDefaults.standard.string(forKey: repoRootDefaultsKey), isLikelyRepoRoot(Path: remembered) {
            return remembered
        }
        if let fromBundle = discoverRepoRootNear(path: Bundle.main.bundleURL.path) {
            return fromBundle
        }
        if let fromCwd = discoverRepoRootNear(path: FileManager.default.currentDirectoryPath) {
            return fromCwd
        }
        return FileManager.default.currentDirectoryPath
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
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
        let hints = errorHints(for: trimmed)
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
        notifications.insert(notification, at: 0)
        if notifications.count > 200 {
            notifications = Array(notifications.prefix(200))
        }
        if showToast {
            showToastNotification(notification)
        }
    }

    private func showToastNotification(_ notification: NotificationRecord) {
        toastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            activeToast = notification
        }
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            await MainActor.run {
                guard self.activeToast?.id == notification.id else {
                    return
                }
                withAnimation(.easeIn(duration: 0.2)) {
                    self.activeToast = nil
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

    private func errorHints(for message: String) -> (likelyCause: String?, suggestedAction: String?) {
        let lower = message.lowercased()
        if lower.contains("no module named") || lower.contains("modulenotfounderror") {
            return (
                likelyCause: "Python dependencies are missing or PYTHONPATH/venv is not configured for this workspace.",
                suggestedAction: "Set repo root to this repository and install dependencies in `.venv` (`pip install -e \".[dev]\"` plus runtime extras)."
            )
        }
        if lower.contains("invalid repo root") || lower.contains("bridge script not found") {
            return (
                likelyCause: "Repo root does not point to the stopmo-xcode project root.",
                suggestedAction: "In Setup, choose a repo root containing `pyproject.toml` and `src/stopmo_xcode`."
            )
        }
        if lower.contains("permission") || lower.contains("not allowed") || lower.contains("operation not permitted") {
            return (
                likelyCause: "macOS file/system permission access was denied.",
                suggestedAction: "Re-select workspace access in Setup and allow the requested permission prompts."
            )
        }
        if lower.contains("ffmpeg") {
            return (
                likelyCause: "FFmpeg is missing or unavailable in PATH.",
                suggestedAction: "Install FFmpeg and run Check Runtime Health to verify dependency availability."
            )
        }
        if lower.contains("decode") || lower.contains("raw") {
            return (
                likelyCause: "Input frame decode failed for the selected file.",
                suggestedAction: "Verify file exists/is supported and inspect Logs & Diagnostics for decode warnings."
            )
        }
        return (
            likelyCause: "The backend operation failed while processing the request.",
            suggestedAction: "Check Logs & Diagnostics and retry the operation after correcting config/runtime issues."
        )
    }
}
