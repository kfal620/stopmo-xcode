import XCTest
@testable import StopmoXcodeGUI

final class KeyValueRowLayoutResolverTests: XCTestCase {
    func testAdaptiveLayoutUsesInlineForShortValuesAtComfortableWidths() {
        let resolved = KeyValueRowLayoutResolver.resolvedLayout(
            requested: .adaptive(availableWidth: 520),
            value: "Healthy",
            valueStyle: .standard
        )

        XCTAssertEqual(resolved, .inline)
    }

    func testAdaptiveLayoutStacksLongValuesOrTightWidths() {
        let longValue = "This is a much longer diagnostic explanation that should not be squeezed into one narrow inline row."

        let longResolved = KeyValueRowLayoutResolver.resolvedLayout(
            requested: .adaptive(availableWidth: 520),
            value: longValue,
            valueStyle: .standard
        )
        let tightResolved = KeyValueRowLayoutResolver.resolvedLayout(
            requested: .adaptive(availableWidth: 300),
            value: "Healthy",
            valueStyle: .standard
        )

        XCTAssertEqual(longResolved, .stacked)
        XCTAssertEqual(tightResolved, .stacked)
    }

    func testAdaptiveLayoutAlwaysStacksPathValues() {
        let resolved = KeyValueRowLayoutResolver.resolvedLayout(
            requested: .adaptive(availableWidth: 800),
            value: "/Users/kyle/Developer/stopmo-xcode/config/sample.yaml",
            valueStyle: .path
        )

        XCTAssertEqual(resolved, .stacked)
    }
}
