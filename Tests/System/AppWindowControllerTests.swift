import AppKit
import XCTest
@testable import MouseLens

@MainActor
final class AppWindowControllerTests: XCTestCase {
    func testCaptureToolbarOriginIsCenteredNearBottomOfVisibleFrame() {
        let visibleFrame = NSRect(x: 1000, y: 200, width: 1600, height: 900)
        let toolbarSize = NSSize(width: 1120, height: 128)

        let origin = AppWindowController.captureToolbarOrigin(
            toolbarSize: toolbarSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 1240, accuracy: 0.001)
        XCTAssertEqual(origin.y, 245, accuracy: 0.001)
    }

}
