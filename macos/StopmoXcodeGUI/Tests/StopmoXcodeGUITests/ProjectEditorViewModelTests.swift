import XCTest
@testable import StopmoXcodeGUI

@MainActor
final class ProjectEditorViewModelTests: XCTestCase {
    func testBootstrapAndDiscardFlowTracksUnsavedChanges() {
        let vm = ProjectEditorViewModel()
        let initial = StopmoConfigDocument.empty

        vm.bootstrapIfNeeded(from: initial)
        XCTAssertFalse(vm.hasUnsavedChanges)

        vm.draftConfig.watch.maxWorkers += 1
        XCTAssertTrue(vm.hasUnsavedChanges)

        XCTAssertTrue(vm.discardChanges())
        XCTAssertFalse(vm.hasUnsavedChanges)
        XCTAssertEqual(vm.draftConfig.watch.maxWorkers, initial.watch.maxWorkers)
    }

    func testDiscardWithoutBaselineReturnsFalse() {
        let vm = ProjectEditorViewModel()
        XCTAssertFalse(vm.discardChanges())
    }

    func testAcceptLoadedConfigResetsBaselineAndDraft() {
        let vm = ProjectEditorViewModel()
        vm.bootstrapIfNeeded(from: .empty)
        vm.draftConfig.output.framerate = 30
        XCTAssertTrue(vm.hasUnsavedChanges)

        var loaded = StopmoConfigDocument.empty
        loaded.pipeline.targetEi = 1280
        loaded.output.framerate = 25

        vm.acceptLoadedConfig(loaded)
        XCTAssertFalse(vm.hasUnsavedChanges)
        XCTAssertEqual(vm.draftConfig.pipeline.targetEi, 1280)
        XCTAssertEqual(vm.draftConfig.output.framerate, 25)
    }

    func testApplyPresetChangesDraftOnly() {
        let vm = ProjectEditorViewModel()
        vm.bootstrapIfNeeded(from: .empty)

        var preset = StopmoConfigDocument.empty
        preset.watch.maxWorkers = 9
        vm.applyPreset(preset)

        XCTAssertTrue(vm.hasUnsavedChanges)
        XCTAssertEqual(vm.draftConfig.watch.maxWorkers, 9)
    }

    func testMatrixHelpers() {
        let vm = ProjectEditorViewModel()
        vm.bootstrapIfNeeded(from: .empty)

        let payload = vm.matrixPayloadForCopy()
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.split(separator: "\n").count, 3)

        let matrix: [[Double]] = [[0.9, 0.1, 0.0], [0.0, 1.0, 0.0], [0.0, 0.2, 0.8]]
        vm.applyMatrix(matrix)
        XCTAssertEqual(vm.draftConfig.pipeline.cameraToReferenceMatrix, matrix)

        vm.draftConfig.pipeline.cameraToReferenceMatrix = [[1, 2], [3]]
        XCTAssertNil(vm.matrixPayloadForCopy())
    }
}
