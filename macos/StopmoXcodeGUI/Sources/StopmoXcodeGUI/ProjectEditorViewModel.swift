import Foundation

@MainActor
final class ProjectEditorViewModel: ObservableObject {
    @Published var draftConfig: StopmoConfigDocument = .empty
    @Published private(set) var baselineConfig: StopmoConfigDocument = .empty
    @Published private(set) var baselineInitialized: Bool = false

    var hasUnsavedChanges: Bool {
        guard baselineInitialized else {
            return false
        }
        return !configsEqual(draftConfig, baselineConfig)
    }

    func bootstrapIfNeeded(from config: StopmoConfigDocument) {
        guard !baselineInitialized else {
            return
        }
        acceptLoadedConfig(config)
    }

    func acceptLoadedConfig(_ config: StopmoConfigDocument) {
        draftConfig = config
        baselineConfig = config
        baselineInitialized = true
    }

    @discardableResult
    func discardChanges() -> Bool {
        guard baselineInitialized else {
            return false
        }
        draftConfig = baselineConfig
        return true
    }

    func applyPreset(_ preset: StopmoConfigDocument) {
        draftConfig = preset
    }

    func resetMatrixIdentity() {
        draftConfig.pipeline.cameraToReferenceMatrix = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    }

    func matrixPayloadForCopy() -> String? {
        let matrix = draftConfig.pipeline.cameraToReferenceMatrix
        guard matrix.count == 3, matrix.allSatisfy({ $0.count == 3 }) else {
            return nil
        }
        let lines = matrix.map { row in row.map { "\($0)" }.joined(separator: " ") }
        return lines.joined(separator: "\n")
    }

    func applyMatrix(_ matrix: [[Double]]) {
        draftConfig.pipeline.cameraToReferenceMatrix = matrix
    }

    private func configsEqual(_ lhs: StopmoConfigDocument, _ rhs: StopmoConfigDocument) -> Bool {
        guard let left = configData(lhs), let right = configData(rhs) else {
            return false
        }
        return left == right
    }

    private func configData(_ config: StopmoConfigDocument) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(config)
    }
}
