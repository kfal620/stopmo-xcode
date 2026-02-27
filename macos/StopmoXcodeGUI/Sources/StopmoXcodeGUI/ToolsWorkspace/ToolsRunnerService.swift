import Foundation

struct ToolsRunnerService {
    func runTranscodeOne(
        repoRoot: String,
        configPath: String,
        inputPath: String,
        outputDir: String?
    ) async throws -> ToolOperationEnvelope {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().transcodeOne(
                repoRoot: repoRoot,
                configPath: configPath,
                inputPath: inputPath,
                outputDir: outputDir
            )
        }.value
    }

    func runSuggestMatrix(
        repoRoot: String,
        inputPath: String,
        cameraMake: String?,
        cameraModel: String?,
        writeJson: String?
    ) async throws -> ToolOperationEnvelope {
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().suggestMatrix(
                repoRoot: repoRoot,
                inputPath: inputPath,
                cameraMake: cameraMake,
                cameraModel: cameraModel,
                writeJson: writeJson
            )
        }.value
    }

    func runDpxToProres(
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
}
