import Foundation
import Darwin

enum BridgeError: Error, LocalizedError {
    case missingRepoRoot(String)
    case processFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRepoRoot(let root):
            return "Invalid repo root: \(root)"
        case .processFailed(let message):
            return message
        case .decodeFailed(let message):
            return message
        }
    }
}

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

struct BridgeClient: Sendable {
    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(value)
    }

    private func pythonExecutable(repoRoot: String) -> String {
        let venv = "\(repoRoot)/.venv/bin/python"
        if FileManager.default.isExecutableFile(atPath: venv) {
            return venv
        }
        return "/usr/bin/python3"
    }

    private func isRepoRoot(_ path: String) -> Bool {
        let fm = FileManager.default
        let pyproject = (path as NSString).appendingPathComponent("pyproject.toml")
        let bridgeScript = (path as NSString).appendingPathComponent("src/stopmo_xcode/gui_bridge.py")
        return fm.fileExists(atPath: pyproject) && fm.fileExists(atPath: bridgeScript)
    }

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

    private func resolveRepoRoot(_ repoRoot: String) -> String {
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

    private func runBridge(
        repoRoot: String,
        arguments: [String],
        stdin: Data? = nil,
        timeoutSeconds: TimeInterval = 20.0
    ) throws -> Data {
        let resolvedRoot = resolveRepoRoot(repoRoot)
        let rootURL = URL(fileURLWithPath: resolvedRoot)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw BridgeError.missingRepoRoot(resolvedRoot)
        }
        let bridgeScript = "\(resolvedRoot)/src/stopmo_xcode/gui_bridge.py"
        guard FileManager.default.fileExists(atPath: bridgeScript) else {
            throw BridgeError.missingRepoRoot("Bridge script not found under repo root: \(resolvedRoot)")
        }

        let process = Process()
        process.currentDirectoryURL = rootURL
        process.executableURL = URL(fileURLWithPath: pythonExecutable(repoRoot: resolvedRoot))
        process.arguments = [bridgeScript] + arguments
        var env = ProcessInfo.processInfo.environment
        let srcPath = "\(resolvedRoot)/src"
        if let existing = env["PYTHONPATH"], !existing.isEmpty {
            env["PYTHONPATH"] = "\(srcPath):\(existing)"
        } else {
            env["PYTHONPATH"] = srcPath
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
