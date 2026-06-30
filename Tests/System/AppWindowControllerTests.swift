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

    func testPreparingCapturePanelEstablishesSizeBeforePositioning() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        AppWindowController.prepareCaptureSetupPanelForDisplay(panel)
        let expectedFrameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: AppWindowController.captureSetupContentSize)
        ).size

        XCTAssertEqual(panel.frame.width, expectedFrameSize.width, accuracy: 0.001)
        XCTAssertEqual(panel.frame.height, expectedFrameSize.height, accuracy: 0.001)
    }

}
