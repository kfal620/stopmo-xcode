import XCTest
import AppKit
@testable import StopmoXcodeGUI

@MainActor
final class ShotThumbnailImageStoreTests: XCTestCase {
    func testCacheKeyChangesWithPathAndReloadKey() {
        ShotThumbnailImageStore.shared.clear()
        let a = ShotThumbnailImageStore.cacheKey(path: "/tmp/a.jpg", reloadKey: "one")
        let b = ShotThumbnailImageStore.cacheKey(path: "/tmp/a.jpg", reloadKey: "two")
        let c = ShotThumbnailImageStore.cacheKey(path: "/tmp/b.jpg", reloadKey: "one")

        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testStoreAndLookupReuseCachedImage() {
        ShotThumbnailImageStore.shared.clear()
        let key = ShotThumbnailImageStore.cacheKey(path: "/tmp/a.jpg", reloadKey: "one")
        let image = NSImage(size: NSSize(width: 8, height: 8))

        ShotThumbnailImageStore.shared.store(image, for: key)

        let cached = ShotThumbnailImageStore.shared.image(for: key)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.size.width, 8)
        XCTAssertEqual(cached?.size.height, 8)
    }

    func testStoringNilClearsCachedEntry() {
        ShotThumbnailImageStore.shared.clear()
        let key = ShotThumbnailImageStore.cacheKey(path: "/tmp/a.jpg", reloadKey: "one")
        let image = NSImage(size: NSSize(width: 4, height: 4))

        ShotThumbnailImageStore.shared.store(image, for: key)
        ShotThumbnailImageStore.shared.store(nil, for: key)

        XCTAssertNil(ShotThumbnailImageStore.shared.image(for: key))
    }
}
