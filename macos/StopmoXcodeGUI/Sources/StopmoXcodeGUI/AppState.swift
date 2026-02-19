import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    @Published var presentedError: PresentedError?
    @Published var isBusy: Bool = false
    @Published var workspaceAccessActive: Bool = false

    private var monitorTask: Task<Void, Never>?
    private var lastQueueCounts: [String: Int] = [:]
    private var lastWatchRunning: Bool?
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

    func presentError(title: String = "Error", message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        errorMessage = trimmed
        presentedError = PresentedError(title: title, message: trimmed)
        statusMessage = "Error"
    }
}
