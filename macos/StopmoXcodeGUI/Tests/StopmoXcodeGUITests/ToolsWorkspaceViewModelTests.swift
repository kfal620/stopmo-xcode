import XCTest
@testable import StopmoXcodeGUI

final class ToolsWorkspaceViewModelTests: XCTestCase {
    enum StubError: Error {
        case failed
    }

    @MainActor
    func testRunTranscodeOneTransitionsToSucceeded() async {
        let envelope = makeEnvelope(operationId: "tool-op-1", kind: "transcode_one", status: "succeeded")
        let runner = ToolsRunnerService(
            transcodeRunner: { _, _, _, _ in envelope },
            matrixRunner: { _, _, _, _, _ in envelope },
            dpxRunner: { _, _, _, _, _ in envelope }
        )
        let viewModel = ToolsWorkspaceViewModel(defaultTab: .transcode, runner: runner)
        let state = AppState()

        await viewModel.runTranscodeOne(
            state: state,
            inputPath: "/tmp/frame.cr3",
            outputDir: nil,
            onRecents: { _, _ in }
        )

        XCTAssertEqual(viewModel.lastToolStatus, .succeeded)
        XCTAssertFalse(viewModel.isRunningTool)
        XCTAssertEqual(viewModel.activeTool, nil)
        XCTAssertFalse(viewModel.lastToolCompletedLabel.isEmpty)
        XCTAssertEqual(state.statusMessage, "Transcode One completed")
    }

    @MainActor
    func testRunTranscodeOneTransitionsToFailed() async {
        let runner = ToolsRunnerService(
            transcodeRunner: { _, _, _, _ in throw StubError.failed },
            matrixRunner: { _, _, _, _, _ in throw StubError.failed },
            dpxRunner: { _, _, _, _, _ in throw StubError.failed }
        )
        let viewModel = ToolsWorkspaceViewModel(defaultTab: .transcode, runner: runner)
        let state = AppState()

        await viewModel.runTranscodeOne(
            state: state,
            inputPath: "/tmp/frame.cr3",
            outputDir: nil,
            onRecents: { _, _ in }
        )

        XCTAssertEqual(viewModel.lastToolStatus, .failed)
        XCTAssertFalse(viewModel.isRunningTool)
        XCTAssertEqual(state.presentedError?.title, "Transcode One Failed")
    }

    @MainActor
    func testApplySharedDeliveryOperationIngestsOutputsForDeliveryMode() {
        let envelope = makeEnvelope(
            operationId: "deliver-op-1",
            kind: "dpx_to_prores",
            status: "succeeded",
            result: [
                "count": .number(2),
                "total_sequences": .number(2),
                "outputs": .array([.string("/tmp/a.mov"), .string("/tmp/b.mov")]),
            ]
        )
        let viewModel = ToolsWorkspaceViewModel(defaultTab: .dpxProres)

        viewModel.applySharedDeliveryOperationIfAvailable(mode: .deliveryOnly, envelope: envelope)

        XCTAssertEqual(viewModel.lastToolStatus, .succeeded)
        XCTAssertEqual(viewModel.dpxProgressText, "Completed 2 / 2 sequences")
        XCTAssertEqual(viewModel.dpxOutputs, ["/tmp/a.mov", "/tmp/b.mov"])
        XCTAssertEqual(viewModel.latestEvents.count, envelope.events.count)
    }

    @MainActor
    func testApplySharedDeliveryOperationSkipsNonDeliveryMode() {
        let envelope = makeEnvelope(operationId: "deliver-op-2", kind: "dpx_to_prores", status: "succeeded")
        let viewModel = ToolsWorkspaceViewModel(defaultTab: .diagnostics)

        viewModel.applySharedDeliveryOperationIfAvailable(mode: .all, envelope: envelope)

        XCTAssertEqual(viewModel.latestEvents.count, 0)
        XCTAssertEqual(viewModel.lastToolStatus, .idle)
    }

    private func makeEnvelope(
        operationId: String,
        kind: String,
        status: String,
        result: [String: JSONValue] = [
            "count": .number(1),
            "total_sequences": .number(1),
            "outputs": .array([.string("/tmp/shot.mov")]),
        ]
    ) -> ToolOperationEnvelope {
        ToolOperationEnvelope(
            operationId: operationId,
            operation: OperationSnapshotRecord(
                id: operationId,
                kind: kind,
                status: status,
                progress: 1.0,
                createdAtUtc: "2026-02-27T10:00:00Z",
                startedAtUtc: "2026-02-27T10:00:01Z",
                finishedAtUtc: "2026-02-27T10:00:03Z",
                cancelRequested: false,
                cancellable: false,
                error: nil,
                metadata: [:],
                result: result
            ),
            events: [
                OperationEventRecord(
                    seq: 1,
                    operationId: operationId,
                    timestampUtc: "2026-02-27T10:00:01Z",
                    eventType: "start",
                    message: "started",
                    payload: nil
                ),
                OperationEventRecord(
                    seq: 2,
                    operationId: operationId,
                    timestampUtc: "2026-02-27T10:00:03Z",
                    eventType: "complete",
                    message: "completed",
                    payload: nil
                ),
            ]
        )
    }
}
