import XCTest
@testable import StopmoXcodeGUI

final class TrafficLightFrameProjectorTests: XCTestCase {
    func testOffsetsAreAppliedFromOriginalFrames() {
        let originals = TrafficLightFrameProjector.OriginalFrames(
            close: CGRect(x: 14, y: 18, width: 14, height: 14),
            miniaturize: CGRect(x: 36, y: 18, width: 14, height: 14),
            zoom: CGRect(x: 58, y: 18, width: 14, height: 14)
        )

        let projected = TrafficLightFrameProjector.shiftedOrigins(
            from: originals,
            offset: CGSize(width: 8, height: 6)
        )

        XCTAssertEqual(projected.close, CGPoint(x: 22, y: 12))
        XCTAssertEqual(projected.miniaturize, CGPoint(x: 44, y: 12))
        XCTAssertEqual(projected.zoom, CGPoint(x: 66, y: 12))
    }

    func testRepeatedProjectionWithSameInputsIsIdempotent() {
        let originals = TrafficLightFrameProjector.OriginalFrames(
            close: CGRect(x: 16, y: 20, width: 14, height: 14),
            miniaturize: CGRect(x: 38, y: 20, width: 14, height: 14),
            zoom: CGRect(x: 60, y: 20, width: 14, height: 14)
        )
        let offset = CGSize(width: 5, height: 3)

        let first = TrafficLightFrameProjector.shiftedOrigins(from: originals, offset: offset)
        let second = TrafficLightFrameProjector.shiftedOrigins(from: originals, offset: offset)

        XCTAssertEqual(first, second)
    }

    func testChangingOffsetRecalculatesFromOriginalsWithoutDrift() {
        let originals = TrafficLightFrameProjector.OriginalFrames(
            close: CGRect(x: 20, y: 24, width: 14, height: 14),
            miniaturize: CGRect(x: 42, y: 24, width: 14, height: 14),
            zoom: CGRect(x: 64, y: 24, width: 14, height: 14)
        )

        let first = TrafficLightFrameProjector.shiftedOrigins(
            from: originals,
            offset: CGSize(width: 10, height: 8)
        )
        let second = TrafficLightFrameProjector.shiftedOrigins(
            from: originals,
            offset: CGSize(width: 3, height: 2)
        )

        XCTAssertEqual(first.close, CGPoint(x: 30, y: 16))
        XCTAssertEqual(second.close, CGPoint(x: 23, y: 22))
        XCTAssertEqual(second.miniaturize, CGPoint(x: 45, y: 22))
        XCTAssertEqual(second.zoom, CGPoint(x: 67, y: 22))
    }
}
