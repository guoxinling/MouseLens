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

    func testAppCoordinatorTemporarilyHidesFloatingToolbarForRecording() {
        let coordinator = AppCoordinator()

        XCTAssertTrue(coordinator.isFloatingHomeToolbarPresented)

        coordinator.hideFloatingHomeToolbarForRecording()

        XCTAssertFalse(coordinator.isFloatingHomeToolbarPresented)

        coordinator.restoreFloatingHomeToolbarAfterRecordingInterruption()

        XCTAssertTrue(coordinator.isFloatingHomeToolbarPresented)
    }

    func testAppCoordinatorDoesNotReopenToolbarIfUserHadAlreadyHiddenIt() {
        let coordinator = AppCoordinator()
        coordinator.dismissFloatingHomeToolbar()

        coordinator.hideFloatingHomeToolbarForRecording()
        coordinator.restoreFloatingHomeToolbarAfterRecordingInterruption()

        XCTAssertFalse(coordinator.isFloatingHomeToolbarPresented)
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

    func testPresenterBubbleDragSnapsToVisibleFrameEdges() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let bubbleSize = NSSize(width: 160, height: 160)

        let bottomRight = AppWindowController.presenterBubbleNormalizedCenter(
            panelFrame: NSRect(
                x: visibleFrame.maxX - bubbleSize.width,
                y: visibleFrame.minY,
                width: bubbleSize.width,
                height: bubbleSize.height
            ),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(bottomRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y, 1, accuracy: 0.0001)

        let topLeft = AppWindowController.presenterBubbleNormalizedCenter(
            panelFrame: NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - bubbleSize.height,
                width: bubbleSize.width,
                height: bubbleSize.height
            ),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.0001)
    }

    func testPresenterBubblePanelReusesContentForRedundantShow() {
        let style = PresenterBubbleStyle(
            isEnabled: true,
            normalizedCenter: NormalizedPoint(x: 1, y: 1),
            normalizedSize: 0.24,
            cornerRadiusRatio: 0.5,
            shadowOpacity: 0.24
        )
        let trackingFrame = NSRect(x: 100, y: 80, width: 1200, height: 800)

        XCTAssertTrue(
            AppWindowController.shouldReusePresenterBubblePanelContent(
                isVisible: true,
                previousStyle: style,
                newStyle: style,
                previousTrackingFrame: trackingFrame,
                newTrackingFrame: trackingFrame
            )
        )
    }

    func testPresenterBubblePanelRebuildsContentWhenStyleChanges() {
        let previousStyle = PresenterBubbleStyle(
            isEnabled: true,
            normalizedCenter: NormalizedPoint(x: 1, y: 1),
            normalizedSize: 0.24,
            cornerRadiusRatio: 0.5,
            shadowOpacity: 0.24
        )
        let nextStyle = PresenterBubbleStyle(
            isEnabled: true,
            normalizedCenter: NormalizedPoint(x: 0, y: 1),
            normalizedSize: 0.24,
            cornerRadiusRatio: 0.5,
            shadowOpacity: 0.24
        )

        XCTAssertFalse(
            AppWindowController.shouldReusePresenterBubblePanelContent(
                isVisible: true,
                previousStyle: previousStyle,
                newStyle: nextStyle,
                previousTrackingFrame: nil,
                newTrackingFrame: nil
            )
        )
    }

    func testPresenterBubbleDragNearVisibleFrameEdgesSnapsToEdges() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let bubbleSize = NSSize(width: 160, height: 160)

        let bottomRight = AppWindowController.presenterBubbleNormalizedCenter(
            panelFrame: NSRect(
                x: visibleFrame.maxX - bubbleSize.width - 64,
                y: visibleFrame.minY + 56,
                width: bubbleSize.width,
                height: bubbleSize.height
            ),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(bottomRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y, 1, accuracy: 0.0001)
    }

    func testPresenterBubbleDragWithinOneBubbleWidthOfEdgeSnapsToEdge() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let bubbleSize = NSSize(width: 160, height: 160)

        let bottomRight = AppWindowController.presenterBubbleNormalizedCenter(
            panelFrame: NSRect(
                x: visibleFrame.maxX - bubbleSize.width - 132,
                y: visibleFrame.minY + 128,
                width: bubbleSize.width,
                height: bubbleSize.height
            ),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(bottomRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y, 1, accuracy: 0.0001)
    }

    func testPresenterBubbleDragUsesCenterAwayFromEdges() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let center = AppWindowController.presenterBubbleNormalizedCenter(
            panelFrame: NSRect(x: 580, y: 370, width: 160, height: 160),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(center.x, 0.4667, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testWindowTargetFrameConvertsScreenCaptureKitRectToAppKitCoordinates() {
        let screenBounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let screenCaptureKitRect = CGRect(x: 200, y: 120, width: 900, height: 600)

        let appKitRect = ScreenRecorder.appKitViewport(
            fromScreenCaptureKitRect: screenCaptureKitRect,
            screenBounds: screenBounds
        )

        XCTAssertEqual(appKitRect.origin.x, 200, accuracy: 0.0001)
        XCTAssertEqual(appKitRect.origin.y, 262, accuracy: 0.0001)
        XCTAssertEqual(appKitRect.size.width, 900, accuracy: 0.0001)
        XCTAssertEqual(appKitRect.size.height, 600, accuracy: 0.0001)
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

    func testEditorPresentationFrameUsesVisibleFrameForMaximizedPreview() {
        let visibleFrame = NSRect(x: 80, y: 40, width: 1440, height: 900)

        let frame = AppWindowController.editorPresentationFrame(visibleFrame: visibleFrame)

        XCTAssertEqual(frame, visibleFrame)
    }

}
