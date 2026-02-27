import Foundation

/// Service type for tools runner service.
struct ToolsRunnerService {
    typealias TranscodeRunner = @Sendable (_ repoRoot: String, _ configPath: String, _ inputPath: String, _ outputDir: String?) async throws -> ToolOperationEnvelope
    typealias MatrixRunner = @Sendable (_ repoRoot: String, _ inputPath: String, _ cameraMake: String?, _ cameraModel: String?, _ writeJson: String?) async throws -> ToolOperationEnvelope
    typealias DpxRunner = @Sendable (_ repoRoot: String, _ inputDir: String, _ outputDir: String?, _ framerate: Int, _ overwrite: Bool) async throws -> ToolOperationEnvelope

    private let transcodeRunner: TranscodeRunner
    private let matrixRunner: MatrixRunner
    private let dpxRunner: DpxRunner

    init(
        transcodeRunner: @escaping TranscodeRunner = ToolsRunnerService.defaultTranscodeRunner,
        matrixRunner: @escaping MatrixRunner = ToolsRunnerService.defaultMatrixRunner,
        dpxRunner: @escaping DpxRunner = ToolsRunnerService.defaultDpxRunner
    ) {
        self.transcodeRunner = transcodeRunner
        self.matrixRunner = matrixRunner
        self.dpxRunner = dpxRunner
    }

    func runTranscodeOne(
        repoRoot: String,
        configPath: String,
        inputPath: String,
        outputDir: String?
    ) async throws -> ToolOperationEnvelope {
        try await transcodeRunner(repoRoot, configPath, inputPath, outputDir)
    }

    func runSuggestMatrix(
        repoRoot: String,
        inputPath: String,
        cameraMake: String?,
        cameraModel: String?,
        writeJson: String?
    ) async throws -> ToolOperationEnvelope {
        try await matrixRunner(repoRoot, inputPath, cameraMake, cameraModel, writeJson)
    }

    func runDpxToProres(
        repoRoot: String,
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool
    ) async throws -> ToolOperationEnvelope {
        try await dpxRunner(repoRoot, inputDir, outputDir, framerate, overwrite)
    }

    private static let defaultTranscodeRunner: TranscodeRunner = { repoRoot, configPath, inputPath, outputDir in
        try await Task.detached(priority: .userInitiated) {
            try BridgeClient().transcodeOne(
                repoRoot: repoRoot,
                configPath: configPath,
                inputPath: inputPath,
                outputDir: outputDir
            )
        }.value
    }

    private static let defaultMatrixRunner: MatrixRunner = { repoRoot, inputPath, cameraMake, cameraModel, writeJson in
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

    private static let defaultDpxRunner: DpxRunner = { repoRoot, inputDir, outputDir, framerate, overwrite in
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
