import XCTest
@testable import StopmoXcodeGUI

final class ToolsRecentsStoreTests: XCTestCase {
    func testDecodeSkipsEmptyAndWhitespaceRows() {
        let raw = "\n /tmp/a \n\n/tmp/b\n  \n"
        XCTAssertEqual(ToolsRecentsStore.decode(raw), ["/tmp/a", "/tmp/b"])
    }

    func testAppendDeDuplicatesAndCapsList() {
        var raw = ""
        for idx in 0 ... 10 {
            raw = ToolsRecentsStore.append("/tmp/\(idx)", to: raw)
        }
        raw = ToolsRecentsStore.append("/tmp/9", to: raw)

        let values = ToolsRecentsStore.decode(raw)
        XCTAssertEqual(values.first, "/tmp/9")
        XCTAssertEqual(values.count, ToolsRecentsStore.maxEntries)
        XCTAssertEqual(Set(values).count, values.count)
    }
}
