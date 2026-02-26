import XCTest
@testable import StopmoXcodeGUI

final class DeliveryFlowTests: XCTestCase {
    @MainActor
    func testPublishDeliveryOperationUpdatesEnvelopeAndRevision() {
        let state = AppState()
        let envelope = makeEnvelope(operationId: "op-1")

        XCTAssertNil(state.deliveryOperationEnvelope)
        XCTAssertEqual(state.deliveryOperationRevision, 0)

        state.publishDeliveryOperation(envelope)

        XCTAssertEqual(state.deliveryOperationEnvelope?.operationId, "op-1")
        XCTAssertEqual(state.deliveryOperationRevision, 1)
    }

    @MainActor
    func testRunDayWrapBatchDeliveryRequiresInputDirectory() async {
        let state = AppState()

        let result = await state.runDayWrapBatchDelivery(
            inputDir: "   ",
            outputDir: nil,
            framerate: 24,
            overwrite: true
        )

        XCTAssertNil(result)
        XCTAssertNil(state.deliveryOperationEnvelope)
        XCTAssertEqual(state.deliveryOperationRevision, 0)
        XCTAssertEqual(state.notifications.last?.kind, .warning)
        XCTAssertEqual(state.notifications.last?.title, "Input Directory Required")
    }

    private func makeEnvelope(operationId: String) -> ToolOperationEnvelope {
        ToolOperationEnvelope(
            operationId: operationId,
            operation: OperationSnapshotRecord(
                id: operationId,
                kind: "dpx_to_prores",
                status: "succeeded",
                progress: 1.0,
                createdAtUtc: "2026-02-25T10:00:00Z",
                startedAtUtc: "2026-02-25T10:00:01Z",
                finishedAtUtc: "2026-02-25T10:00:10Z",
                cancelRequested: false,
                cancellable: false,
                error: nil,
                metadata: [:],
                result: [
                    "count": .number(1),
                    "total_sequences": .number(1),
                    "outputs": .array([.string("/tmp/shot.mov")]),
                ]
            ),
            events: [
                OperationEventRecord(
                    seq: 1,
                    operationId: operationId,
                    timestampUtc: "2026-02-25T10:00:02Z",
                    eventType: "start",
                    message: "started",
                    payload: nil
                ),
                OperationEventRecord(
                    seq: 2,
                    operationId: operationId,
                    timestampUtc: "2026-02-25T10:00:10Z",
                    eventType: "complete",
                    message: "completed",
                    payload: nil
                ),
            ]
        )
    }
}
