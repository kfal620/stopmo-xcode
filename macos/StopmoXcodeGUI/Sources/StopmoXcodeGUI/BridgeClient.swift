import Foundation
import Darwin

/// Errors surfaced when bridge process launch, routing, or decoding fails.
enum BridgeError: Error, LocalizedError {
    case missingWorkspaceRoot(String)
    case missingRepoRoot(String)
    case processFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspaceRoot(let root):
            return "Invalid workspace root: \(root)"
        case .missingRepoRoot(let root):
            return "Invalid repo root: \(root)"
        case .processFailed(let message):
            return message
        case .decodeFailed(let message):
            return message
        }
    }
}

/// Thread-safe byte accumulator for incremental bridge process output reads.
private final class BridgeOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }
}

/// Bridge transport client that shells out to `gui_bridge.py` JSON commands.
struct BridgeClient: Sendable {
    private enum BridgeRuntimeMode: String, Sendable {
        case bundled
        case external
    }

    /// Resolved launch details for either bundled or external bridge mode.
    private struct BridgeLaunchContext: Sendable {
        var currentDirectory: String
        var executable: String
        var argumentsPrefix: [String]
        var environmentOverrides: [String: String]
    }

    /// Decode bridge JSON response into typed Swift payload.
    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// Encode typed Swift payload into bridge JSON request body.
    private func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(value)
    }

    /// Prefer venv Python from repo root, fallback to system python for bootstrap.
    private func pythonExecutable(repoRoot: String) -> String {
        let venv = "\(repoRoot)/.venv/bin/python"
        if FileManager.default.isExecutableFile(atPath: venv) {
            return venv
        }
        return "/usr/bin/python3"
    }

    /// Heuristic for repo root detection used by external runtime mode.
    private func isRepoRoot(_ path: String) -> Bool {
        let fm = FileManager.default
        let pyproject = (path as NSString).appendingPathComponent("pyproject.toml")
        let bridgeScript = (path as NSString).appendingPathComponent("src/stopmo_xcode/gui_bridge.py")
        return fm.fileExists(atPath: pyproject) && fm.fileExists(atPath: bridgeScript)
    }

    /// Walk parent directories to discover a valid backend repository root.
    private func discoverRepoRoot(startingAt path: String) -> String? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        if !url.hasDirectoryPath {
            url.deleteLastPathComponent()
        }
        for _ in 0..<12 {
            let candidate = url.path
            if isRepoRoot(candidate) {
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

    /// Resolve backend root using env overrides then filesystem discovery fallback.
    private func resolveRepoRoot(_ repoRoot: String) -> String {
        let env = ProcessInfo.processInfo.environment
        for key in ["STOPMO_XCODE_BACKEND_ROOT", "STOPMO_XCODE_ROOT"] {
            if let candidate = env[key], isRepoRoot(candidate) {
                return candidate
            }
        }
        if isRepoRoot(repoRoot) {
            return repoRoot
        }
        if let found = discoverRepoRoot(startingAt: repoRoot) {
            return found
        }
        if let found = discoverRepoRoot(startingAt: FileManager.default.currentDirectoryPath) {
            return found
        }
        if let found = discoverRepoRoot(startingAt: Bundle.main.bundleURL.path) {
            return found
        }
        return repoRoot
    }

    /// Resolve workspace root for sandbox/permission-safe bridge launches.
    private func resolveWorkspaceRoot(_ workspaceRoot: String) -> String {
        let trimmed = workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            return home
        }
        return FileManager.default.currentDirectoryPath
    }

    /// Return packaged bridge launcher path when app is running in bundled mode.
    private func bundledLauncherPath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent("backend/launch_bridge.sh").path {
            candidates.append(resourcePath)
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend/launch_bridge.sh").path)
        for candidate in candidates {
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Build launch context for either bundled runtime or editable external backend.
    private func resolveLaunchContext(workspaceRoot: String) throws -> BridgeLaunchContext {
        let resolvedWorkspace = resolveWorkspaceRoot(workspaceRoot)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedWorkspace, isDirectory: &isDir), isDir.boolValue else {
            throw BridgeError.missingWorkspaceRoot(resolvedWorkspace)
        }

        if let launcher = bundledLauncherPath() {
            return BridgeLaunchContext(
                currentDirectory: resolvedWorkspace,
                executable: launcher,
                argumentsPrefix: [],
                environmentOverrides: [
                    "STOPMO_XCODE_RUNTIME_MODE": BridgeRuntimeMode.bundled.rawValue,
                    "STOPMO_XCODE_WORKSPACE_ROOT": resolvedWorkspace,
                ]
            )
        }

        let resolvedRepoRoot = resolveRepoRoot(workspaceRoot)
        let rootURL = URL(fileURLWithPath: resolvedRepoRoot)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw BridgeError.missingRepoRoot(resolvedRepoRoot)
        }
        let bridgeScript = "\(resolvedRepoRoot)/src/stopmo_xcode/gui_bridge.py"
        guard FileManager.default.fileExists(atPath: bridgeScript) else {
            throw BridgeError.missingRepoRoot("Bridge script not found under repo root: \(resolvedRepoRoot)")
        }

        let srcPath = "\(resolvedRepoRoot)/src"
        var pythonPath = srcPath
        if let existing = ProcessInfo.processInfo.environment["PYTHONPATH"], !existing.isEmpty {
            pythonPath = "\(srcPath):\(existing)"
        }

        return BridgeLaunchContext(
            currentDirectory: resolvedRepoRoot,
            executable: pythonExecutable(repoRoot: resolvedRepoRoot),
            argumentsPrefix: [bridgeScript],
            environmentOverrides: [
                "PYTHONPATH": pythonPath,
                "STOPMO_XCODE_RUNTIME_MODE": BridgeRuntimeMode.external.rawValue,
                "STOPMO_XCODE_BACKEND_ROOT": resolvedRepoRoot,
                "STOPMO_XCODE_WORKSPACE_ROOT": resolvedWorkspace,
            ]
        )
    }

    private func runBridge(
        repoRoot: String,
        arguments: [String],
        stdin: Data? = nil,
        timeoutSeconds: TimeInterval = 20.0
    ) throws -> Data {
        // Execute one bridge command and return merged stdout/stderr JSON payload.
        let launch = try resolveLaunchContext(workspaceRoot: repoRoot)

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: launch.currentDirectory)
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.argumentsPrefix + arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in launch.environmentOverrides {
            env[key] = value
        }
        process.environment = env

        let outPipe = Pipe()
        // Use a single stream and incremental reads to avoid pipe saturation on larger outputs.
        process.standardOutput = outPipe
        process.standardError = outPipe
        let accumulator = BridgeOutputAccumulator()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            accumulator.append(chunk)
        }

        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        let deadline = Date().addingTimeInterval(max(1.0, timeoutSeconds))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            outPipe.fileHandleForReading.readabilityHandler = nil
            var partial = accumulator.snapshot()
            partial.append(outPipe.fileHandleForReading.readDataToEndOfFile())
            let partialText = String(data: partial, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let details = partialText.isEmpty ? "" : "\n\(partialText)"
            throw BridgeError.processFailed(
                "Bridge command timed out after \(Int(timeoutSeconds.rounded()))s: \(arguments.joined(separator: " "))\(details)"
            )
        }

        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        var finalData = accumulator.snapshot()
        finalData.append(outPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: finalData, encoding: .utf8) ?? ""
            throw BridgeError.processFailed(stderrText.isEmpty ? "Bridge process failed" : stderrText)
        }
        return finalData
    }

    func health(repoRoot: String, configPath: String?) throws -> BridgeHealth {
        var args = ["health"]
        if let configPath, !configPath.isEmpty {
            args += ["--config", configPath]
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 15.0)
        return try decodeJSON(BridgeHealth.self, from: data)
    }

    func readConfig(repoRoot: String, configPath: String) throws -> StopmoConfigDocument {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["config-read", "--config", configPath],
            timeoutSeconds: 20.0
        )
        return try decodeJSON(StopmoConfigDocument.self, from: data)
    }

    func writeConfig(repoRoot: String, configPath: String, config: StopmoConfigDocument) throws -> StopmoConfigDocument {
        let payload = try encodeJSON(config)
        _ = try runBridge(
            repoRoot: repoRoot,
            arguments: ["config-write", "--config", configPath],
            stdin: payload,
            timeoutSeconds: 20.0
        )
        return try readConfig(repoRoot: repoRoot, configPath: configPath)
    }

    func queueStatus(repoRoot: String, configPath: String, limit: Int = 200) throws -> QueueSnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["queue-status", "--config", configPath, "--limit", "\(max(1, limit))"],
            timeoutSeconds: 12.0
        )
        return try decodeJSON(QueueSnapshot.self, from: data)
    }

    func queueRetryFailed(repoRoot: String, configPath: String, jobIds: [Int]?) throws -> QueueRetryResult {
        var args = ["queue-retry-failed", "--config", configPath]
        let ids = (jobIds ?? []).filter { $0 > 0 }
        if !ids.isEmpty {
            args.append("--ids")
            args += ids.map(String.init)
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 20.0)
        return try decodeJSON(QueueRetryResult.self, from: data)
    }

    func shotsSummary(repoRoot: String, configPath: String, limit: Int = 500) throws -> ShotsSummarySnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["shots-summary", "--config", configPath, "--limit", "\(max(1, limit))"],
            timeoutSeconds: 18.0
        )
        return try decodeJSON(ShotsSummarySnapshot.self, from: data)
    }

    func watchStart(repoRoot: String, configPath: String) throws -> WatchServiceState {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["watch-start", "--config", configPath],
            timeoutSeconds: 14.0
        )
        return try decodeJSON(WatchServiceState.self, from: data)
    }

    func watchStop(repoRoot: String, configPath: String, timeoutSeconds: Double = 5.0) throws -> WatchServiceState {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["watch-stop", "--config", configPath, "--timeout", "\(max(0.5, timeoutSeconds))"],
            timeoutSeconds: max(10.0, timeoutSeconds + 5.0)
        )
        return try decodeJSON(WatchServiceState.self, from: data)
    }

    func watchState(repoRoot: String, configPath: String, limit: Int = 200, tailLines: Int = 40) throws -> WatchServiceState {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: [
                "watch-state",
                "--config",
                configPath,
                "--limit",
                "\(max(1, limit))",
                "--tail",
                "\(max(0, tailLines))"
            ],
            timeoutSeconds: 8.0
        )
        return try decodeJSON(WatchServiceState.self, from: data)
    }

    func configValidate(repoRoot: String, configPath: String) throws -> ConfigValidationSnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["config-validate", "--config", configPath],
            timeoutSeconds: 15.0
        )
        return try decodeJSON(ConfigValidationSnapshot.self, from: data)
    }

    func watchPreflight(repoRoot: String, configPath: String) throws -> WatchPreflight {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["watch-preflight", "--config", configPath],
            timeoutSeconds: 20.0
        )
        return try decodeJSON(WatchPreflight.self, from: data)
    }

    func transcodeOne(
        repoRoot: String,
        configPath: String,
        inputPath: String,
        outputDir: String?
    ) throws -> ToolOperationEnvelope {
        var args = ["transcode-one", "--config", configPath, "--input", inputPath]
        if let outputDir, !outputDir.isEmpty {
            args += ["--output-dir", outputDir]
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 1_800.0)
        return try decodeJSON(ToolOperationEnvelope.self, from: data)
    }

    func suggestMatrix(
        repoRoot: String,
        inputPath: String,
        cameraMake: String?,
        cameraModel: String?,
        writeJson: String?
    ) throws -> ToolOperationEnvelope {
        var args = ["suggest-matrix", "--input", inputPath]
        if let cameraMake, !cameraMake.isEmpty {
            args += ["--camera-make", cameraMake]
        }
        if let cameraModel, !cameraModel.isEmpty {
            args += ["--camera-model", cameraModel]
        }
        if let writeJson, !writeJson.isEmpty {
            args += ["--write-json", writeJson]
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 180.0)
        return try decodeJSON(ToolOperationEnvelope.self, from: data)
    }

    func dpxToProres(
        repoRoot: String,
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool
    ) throws -> ToolOperationEnvelope {
        var args = ["dpx-to-prores", "--input-dir", inputDir, "--framerate", "\(max(1, framerate))"]
        if let outputDir, !outputDir.isEmpty {
            args += ["--out-dir", outputDir]
        }
        args += [overwrite ? "--overwrite" : "--no-overwrite"]
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 7_200.0)
        return try decodeJSON(ToolOperationEnvelope.self, from: data)
    }

    func logsDiagnostics(
        repoRoot: String,
        configPath: String,
        severity: String?,
        limit: Int = 400
    ) throws -> LogsDiagnosticsSnapshot {
        var args = ["logs-diagnostics", "--config", configPath, "--limit", "\(max(1, limit))"]
        if let severity, !severity.isEmpty {
            args += ["--severity", severity]
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 16.0)
        return try decodeJSON(LogsDiagnosticsSnapshot.self, from: data)
    }

    func historySummary(
        repoRoot: String,
        configPath: String,
        limit: Int = 30,
        gapMinutes: Int = 30
    ) throws -> HistorySummarySnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: [
                "history-summary",
                "--config",
                configPath,
                "--limit",
                "\(max(1, limit))",
                "--gap-minutes",
                "\(max(1, gapMinutes))",
            ],
            timeoutSeconds: 20.0
        )
        return try decodeJSON(HistorySummarySnapshot.self, from: data)
    }

    func copyDiagnosticsBundle(
        repoRoot: String,
        configPath: String,
        outDir: String?
    ) throws -> DiagnosticsBundleResult {
        var args = ["copy-diagnostics-bundle", "--config", configPath]
        if let outDir, !outDir.isEmpty {
            args += ["--out-dir", outDir]
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args, timeoutSeconds: 60.0)
        return try decodeJSON(DiagnosticsBundleResult.self, from: data)
    }
}
