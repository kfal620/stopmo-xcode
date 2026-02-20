import Foundation

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
        stdin: Data? = nil
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
        // Use a single pipe for stdout/stderr to avoid deadlock on large outputs.
        process.standardOutput = outPipe
        process.standardError = outPipe

        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: outData, encoding: .utf8) ?? ""
            throw BridgeError.processFailed(stderrText.isEmpty ? "Bridge process failed" : stderrText)
        }
        return outData
    }

    func health(repoRoot: String, configPath: String?) throws -> BridgeHealth {
        var args = ["health"]
        if let configPath, !configPath.isEmpty {
            args += ["--config", configPath]
        }
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
        return try decodeJSON(BridgeHealth.self, from: data)
    }

    func readConfig(repoRoot: String, configPath: String) throws -> StopmoConfigDocument {
        let data = try runBridge(repoRoot: repoRoot, arguments: ["config-read", "--config", configPath])
        return try decodeJSON(StopmoConfigDocument.self, from: data)
    }

    func writeConfig(repoRoot: String, configPath: String, config: StopmoConfigDocument) throws -> StopmoConfigDocument {
        let payload = try encodeJSON(config)
        _ = try runBridge(
            repoRoot: repoRoot,
            arguments: ["config-write", "--config", configPath],
            stdin: payload
        )
        return try readConfig(repoRoot: repoRoot, configPath: configPath)
    }

    func queueStatus(repoRoot: String, configPath: String, limit: Int = 200) throws -> QueueSnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["queue-status", "--config", configPath, "--limit", "\(max(1, limit))"]
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
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
        return try decodeJSON(QueueRetryResult.self, from: data)
    }

    func shotsSummary(repoRoot: String, configPath: String, limit: Int = 500) throws -> ShotsSummarySnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["shots-summary", "--config", configPath, "--limit", "\(max(1, limit))"]
        )
        return try decodeJSON(ShotsSummarySnapshot.self, from: data)
    }

    func watchStart(repoRoot: String, configPath: String) throws -> WatchServiceState {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["watch-start", "--config", configPath]
        )
        return try decodeJSON(WatchServiceState.self, from: data)
    }

    func watchStop(repoRoot: String, configPath: String, timeoutSeconds: Double = 5.0) throws -> WatchServiceState {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["watch-stop", "--config", configPath, "--timeout", "\(max(0.5, timeoutSeconds))"]
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
            ]
        )
        return try decodeJSON(WatchServiceState.self, from: data)
    }

    func configValidate(repoRoot: String, configPath: String) throws -> ConfigValidationSnapshot {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["config-validate", "--config", configPath]
        )
        return try decodeJSON(ConfigValidationSnapshot.self, from: data)
    }

    func watchPreflight(repoRoot: String, configPath: String) throws -> WatchPreflight {
        let data = try runBridge(
            repoRoot: repoRoot,
            arguments: ["watch-preflight", "--config", configPath]
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
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
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
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
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
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
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
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
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
            ]
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
        let data = try runBridge(repoRoot: repoRoot, arguments: args)
        return try decodeJSON(DiagnosticsBundleResult.self, from: data)
    }
}
