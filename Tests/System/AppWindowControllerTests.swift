import AppKit
import XCTest
@testable import MouseLens

@MainActor
final class AppWindowControllerTests: XCTestCase {
    func testAppCoordinatorDismissesAndReopensFloatingHomeToolbar() {
        let coordinator = AppCoordinator()

        XCTAssertTrue(coordinator.isFloatingHomeToolbarPresented)

        coordinator.dismissFloatingHomeToolbar()
        XCTAssertFalse(coordinator.isFloatingHomeToolbarPresented)

        coordinator.presentFloatingHomeToolbar()
        XCTAssertTrue(coordinator.isFloatingHomeToolbarPresented)
    }

    func testHomeToolbarUsesFloatingPanelOutsideXCTest() {
        XCTAssertEqual(
            HomeToolbarPresentationMode.current(environment: [:]),
            .floatingPanel
        )
        XCTAssertFalse(HomeToolbarPresentationMode.floatingPanel.rendersIntoPrimaryWindow)
    }

    func testHomeToolbarUsesPrimaryWindowInsideXCTest() {
        XCTAssertEqual(
            HomeToolbarPresentationMode.current(
                environment: ["XCTestConfigurationFilePath": "/tmp/config.xctest"]
            ),
            .primaryWindow
        )
        XCTAssertTrue(HomeToolbarPresentationMode.primaryWindow.rendersIntoPrimaryWindow)
    }

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

    func testCaptureToolbarOriginRespectsConfiguredBottomMargin() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let toolbarSize = NSSize(width: 1120, height: 96)

        let origin = AppWindowController.captureToolbarOrigin(
            toolbarSize: toolbarSize,
            visibleFrame: visibleFrame,
            bottomMargin: 45
        )

        XCTAssertEqual(origin.x, 196, accuracy: 0.001)
        XCTAssertEqual(origin.y, 45, accuracy: 0.001)
    }

    func testCaptureToolbarCollectionBehaviorMatchesFullscreenFloatingToolbar() {
        let behavior = AppWindowController.captureToolbarCollectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.stationary))
    }

    func testApplyEditorWindowLayoutRestoresNormalLevelAndSpaceBehavior() {
        let controller = AppWindowController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 96),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
        window.level = .statusBar

        controller.attachAppWindow(window)
        controller.applyEditorWindowLayout()

        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
    }

}
