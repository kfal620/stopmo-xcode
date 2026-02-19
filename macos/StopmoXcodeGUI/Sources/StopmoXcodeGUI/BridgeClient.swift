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

    private func runBridge(
        repoRoot: String,
        arguments: [String],
        stdin: Data? = nil
    ) throws -> Data {
        let rootURL = URL(fileURLWithPath: repoRoot)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw BridgeError.missingRepoRoot(repoRoot)
        }

        let process = Process()
        process.currentDirectoryURL = rootURL
        process.executableURL = URL(fileURLWithPath: pythonExecutable(repoRoot: repoRoot))
        process.arguments = ["-m", "stopmo_xcode.gui_bridge"] + arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: errData, encoding: .utf8) ?? ""
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
}
