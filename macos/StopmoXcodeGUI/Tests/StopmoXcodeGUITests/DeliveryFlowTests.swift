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

    @MainActor
    func testDeliveryRunStateBeginsForBatchBeforeBridgeResult() {
        let state = AppState()

        state.beginDeliveryRun(kind: .dayWrapBatch, total: 0, label: "Running day wrap batch...")

        XCTAssertEqual(state.deliveryRunState.kind, .dayWrapBatch)
        XCTAssertEqual(state.deliveryRunState.status, .running)
        XCTAssertEqual(state.deliveryRunState.total, 0)
        XCTAssertEqual(state.deliveryRunState.completed, 0)
        XCTAssertEqual(state.deliveryRunState.failed, 0)
        XCTAssertEqual(state.deliveryRunState.progress, 0)
        XCTAssertEqual(state.deliveryRunState.activeLabel, "Running day wrap batch...")
        XCTAssertNotNil(state.deliveryRunState.startedAtUtc)
    }

    @MainActor
    func testDeliverShotsProgressTransitionsToSucceeded() {
        let state = AppState()

        state.beginDeliveryRun(kind: .selectedShots, total: 2, label: "Starting selected delivery...")
        state.updateDeliveryRunProgress(completed: 1, failed: 0, activeLabel: "Processed 1 / 2")
        state.finishDeliveryRun(
            status: .succeeded,
            outputs: ["/tmp/a.mov", "/tmp/b.mov"],
            completed: 2,
            total: 2,
            failed: 0,
            activeLabel: "Completed successfully"
        )

        XCTAssertEqual(state.deliveryRunState.status, .succeeded)
        XCTAssertEqual(state.deliveryRunState.completed, 2)
        XCTAssertEqual(state.deliveryRunState.failed, 0)
        XCTAssertEqual(state.deliveryRunState.total, 2)
        XCTAssertEqual(state.deliveryRunState.progress, 1.0)
        XCTAssertEqual(state.deliveryRunState.latestOutputs.count, 2)
        XCTAssertNotNil(state.deliveryRunState.finishedAtUtc)
    }

    @MainActor
    func testDeliverShotsProgressTransitionsToPartialOnMixedResults() {
        let state = AppState()

        state.beginDeliveryRun(kind: .selectedShots, total: 3, label: "Starting selected delivery...")
        state.updateDeliveryRunProgress(completed: 1, failed: 1, activeLabel: "Processed 2 / 3")
        state.finishDeliveryRun(
            status: .partial,
            outputs: ["/tmp/a.mov"],
            completed: 1,
            total: 3,
            failed: 2,
            activeLabel: "Completed with some failures"
        )

        XCTAssertEqual(state.deliveryRunState.status, .partial)
        XCTAssertEqual(state.deliveryRunState.completed, 1)
        XCTAssertEqual(state.deliveryRunState.failed, 2)
        XCTAssertEqual(state.deliveryRunState.total, 3)
        XCTAssertEqual(state.deliveryRunState.progress, 1.0)
        XCTAssertEqual(state.deliveryRunState.latestOutputs, ["/tmp/a.mov"])
    }

    @MainActor
    func testDeliveryRunStateRecordsEventsInOrder() {
        let state = AppState()

        state.beginDeliveryRun(kind: .selectedShots, total: 1, label: "Starting")
        state.appendDeliveryEvent(tone: .warning, title: "Start", detail: "Started")
        state.appendDeliveryEvent(tone: .success, title: "Done", detail: "Finished")

        XCTAssertEqual(state.deliveryRunState.events.count, 2)
        XCTAssertEqual(state.deliveryRunState.events.first?.title, "Done")
        XCTAssertEqual(state.deliveryRunState.events.last?.title, "Start")
    }

    @MainActor
    func testSelectionPruneKeepsOnlyValidReadyShots() {
        let state = AppState()

        let snapshot = ShotsSummarySnapshot(
            dbPath: "/tmp/queue.db",
            count: 3,
            shots: [
                makeShot(name: "SHOT_A", state: "done", total: 10, done: 10, failed: 0, inflight: 0),
                makeShot(name: "SHOT_B", state: "processing", total: 10, done: 6, failed: 0, inflight: 2),
                makeShot(name: "SHOT_C", state: "issues", total: 10, done: 3, failed: 2, inflight: 0),
            ]
        )

        let selected: Set<String> = ["SHOT_A", "SHOT_B", "SHOT_MISSING"]
        let pruned = state.pruneDeliverySelection(selected, from: snapshot)

        XCTAssertEqual(pruned, Set(["SHOT_A"]))
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

    private func makeShot(
        name: String,
        state: String,
        total: Int,
        done: Int,
        failed: Int,
        inflight: Int
    ) -> ShotSummaryRow {
        ShotSummaryRow(
            shotName: name,
            state: state,
            totalFrames: total,
            doneFrames: done,
            failedFrames: failed,
            inflightFrames: inflight,
            progressRatio: total == 0 ? 0 : Double(done) / Double(total),
            lastUpdatedAt: "2026-02-25T10:00:00Z",
            assemblyState: nil,
            outputMovPath: nil,
            reviewMovPath: nil,
            exposureOffsetStops: nil,
            wbMultipliers: nil
        )
    }
}
