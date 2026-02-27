import Foundation

@MainActor
protocol BridgeServicing {
    func health(repoRoot: String, configPath: String) async throws -> BridgeHealth
    func readConfig(repoRoot: String, configPath: String) async throws -> StopmoConfigDocument
    func writeConfig(repoRoot: String, configPath: String, config: StopmoConfigDocument) async throws -> StopmoConfigDocument
    func watchStart(repoRoot: String, configPath: String) async throws -> WatchServiceState
    func watchStop(repoRoot: String, configPath: String) async throws -> WatchServiceState
    func watchState(
        repoRoot: String,
        configPath: String,
        limit: Int,
        tailLines: Int
    ) async throws -> WatchServiceState
    func shotsSummary(repoRoot: String, configPath: String, limit: Int) async throws -> ShotsSummarySnapshot
    func logsDiagnostics(
        repoRoot: String,
        configPath: String,
        severity: String?,
        limit: Int
    ) async throws -> LogsDiagnosticsSnapshot
    func configValidate(repoRoot: String, configPath: String) async throws -> ConfigValidationSnapshot
    func watchPreflight(repoRoot: String, configPath: String) async throws -> WatchPreflight
    func historySummary(
        repoRoot: String,
        configPath: String,
        limit: Int,
        gapMinutes: Int
    ) async throws -> HistorySummarySnapshot
    func dpxToProres(
        repoRoot: String,
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool
    ) async throws -> ToolOperationEnvelope
    func copyDiagnosticsBundle(repoRoot: String, configPath: String, outDir: String?) async throws -> DiagnosticsBundleResult
    func queueRetryFailed(repoRoot: String, configPath: String, jobIds: [Int]?) async throws -> QueueRetryResult
}

@MainActor
struct LiveBridgeService: BridgeServicing {
    func health(repoRoot: String, configPath: String) async throws -> BridgeHealth {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().health(repoRoot: repoRoot, configPath: configPath)
        }.value
    }

    func readConfig(repoRoot: String, configPath: String) async throws -> StopmoConfigDocument {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().readConfig(repoRoot: repoRoot, configPath: configPath)
        }.value
    }

    func writeConfig(repoRoot: String, configPath: String, config: StopmoConfigDocument) async throws -> StopmoConfigDocument {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().writeConfig(repoRoot: repoRoot, configPath: configPath, config: config)
        }.value
    }

    func watchStart(repoRoot: String, configPath: String) async throws -> WatchServiceState {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().watchStart(repoRoot: repoRoot, configPath: configPath)
        }.value
    }

    func watchStop(repoRoot: String, configPath: String) async throws -> WatchServiceState {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().watchStop(repoRoot: repoRoot, configPath: configPath)
        }.value
    }

    func watchState(
        repoRoot: String,
        configPath: String,
        limit: Int,
        tailLines: Int
    ) async throws -> WatchServiceState {
        try await Task.detached(priority: .utility) {
            try BridgeClient().watchState(
                repoRoot: repoRoot,
                configPath: configPath,
                limit: limit,
                tailLines: tailLines
            )
        }.value
    }

    func shotsSummary(repoRoot: String, configPath: String, limit: Int) async throws -> ShotsSummarySnapshot {
        try await Task.detached(priority: .utility) {
            try BridgeClient().shotsSummary(repoRoot: repoRoot, configPath: configPath, limit: limit)
        }.value
    }

    func logsDiagnostics(
        repoRoot: String,
        configPath: String,
        severity: String?,
        limit: Int
    ) async throws -> LogsDiagnosticsSnapshot {
        try await Task.detached(priority: .utility) {
            try BridgeClient().logsDiagnostics(
                repoRoot: repoRoot,
                configPath: configPath,
                severity: severity,
                limit: limit
            )
        }.value
    }

    func configValidate(repoRoot: String, configPath: String) async throws -> ConfigValidationSnapshot {
        try await Task.detached(priority: .utility) {
            try BridgeClient().configValidate(repoRoot: repoRoot, configPath: configPath)
        }.value
    }

    func watchPreflight(repoRoot: String, configPath: String) async throws -> WatchPreflight {
        try await Task.detached(priority: .utility) {
            try BridgeClient().watchPreflight(repoRoot: repoRoot, configPath: configPath)
        }.value
    }

    func historySummary(
        repoRoot: String,
        configPath: String,
        limit: Int,
        gapMinutes: Int
    ) async throws -> HistorySummarySnapshot {
        try await Task.detached(priority: .utility) {
            try BridgeClient().historySummary(
                repoRoot: repoRoot,
                configPath: configPath,
                limit: limit,
                gapMinutes: gapMinutes
            )
        }.value
    }

    func dpxToProres(
        repoRoot: String,
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool
    ) async throws -> ToolOperationEnvelope {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().dpxToProres(
                repoRoot: repoRoot,
                inputDir: inputDir,
                outputDir: outputDir,
                framerate: framerate,
                overwrite: overwrite
            )
        }.value
    }

    func copyDiagnosticsBundle(repoRoot: String, configPath: String, outDir: String?) async throws -> DiagnosticsBundleResult {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().copyDiagnosticsBundle(
                repoRoot: repoRoot,
                configPath: configPath,
                outDir: outDir
            )
        }.value
    }

    func queueRetryFailed(repoRoot: String, configPath: String, jobIds: [Int]?) async throws -> QueueRetryResult {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().queueRetryFailed(
                repoRoot: repoRoot,
                configPath: configPath,
                jobIds: jobIds
            )
        }.value
    }
}
