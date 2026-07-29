import XCTest
@testable import MouseLens

final class WindowSelectionPriorityTests: XCTestCase {
    func testCurrentProcessWindowIsExcludedEvenWhenBundleIdentifierIsMissing() {
        XCTAssertTrue(
            ScreenRecorder.isWindowOwnedByCurrentApp(
                bundleIdentifier: nil,
                processID: 1234,
                applicationName: nil,
                currentBundleIdentifier: "com.guoxl.MouseLens",
                currentProcessID: 1234,
                currentApplicationName: "MouseLens"
            )
        )
    }

    func testOtherProcessWindowIsNotExcludedWhenBundleIdentifierDiffers() {
        XCTAssertFalse(
            ScreenRecorder.isWindowOwnedByCurrentApp(
                bundleIdentifier: "com.apple.Safari",
                processID: 5678,
                applicationName: "Safari",
                currentBundleIdentifier: "com.guoxl.MouseLens",
                currentProcessID: 1234,
                currentApplicationName: "MouseLens"
            )
        )
    }

    func testCurrentAppWindowIsExcludedWhenOnlyApplicationNameMatches() {
        XCTAssertTrue(
            ScreenRecorder.isWindowOwnedByCurrentApp(
                bundleIdentifier: nil,
                processID: nil,
                applicationName: "MouseLens",
                currentBundleIdentifier: "com.guoxl.MouseLens",
                currentProcessID: 1234,
                currentApplicationName: "MouseLens"
            )
        )
    }

    func testFrontmostActiveWindowOutranksLargerBackgroundWindow() {
        let frontmost = CaptureWindowPriority(
            isFrontmostApp: true,
            isActive: true,
            zIndex: 0,
            windowLayer: 0,
            area: 600_000
        )
        let background = CaptureWindowPriority(
            isFrontmostApp: false,
            isActive: false,
            zIndex: 1,
            windowLayer: 0,
            area: 4_000_000
        )

        XCTAssertGreaterThan(frontmost, background)
    }

    func testLowerWindowLayerOutranksHigherLayerWhenAppAndActiveStateMatch() {
        let topLayer = CaptureWindowPriority(
            isFrontmostApp: true,
            isActive: true,
            zIndex: 0,
            windowLayer: 0,
            area: 900_000
        )
        let deeperLayer = CaptureWindowPriority(
            isFrontmostApp: true,
            isActive: true,
            zIndex: 1,
            windowLayer: 12,
            area: 1_400_000
        )

        XCTAssertGreaterThan(topLayer, deeperLayer)
    }

    func testLowerZIndexOutranksLargerWindowWhenSignalsOtherwiseMatch() {
        let topmost = CaptureWindowPriority(
            isFrontmostApp: true,
            isActive: true,
            zIndex: 0,
            windowLayer: 0,
            area: 700_000
        )
        let background = CaptureWindowPriority(
            isFrontmostApp: true,
            isActive: true,
            zIndex: 4,
            windowLayer: 0,
            area: 2_600_000
        )

        XCTAssertGreaterThan(topmost, background)
    }

    func testFullscreenBrowserAuxiliaryStripIsExcludedByFrameShape() {
        XCTAssertTrue(
            ScreenRecorder.isLikelyAuxiliaryWindowFrame(
                CGRect(x: 0, y: 0, width: 1470, height: 124)
            )
        )
    }

    func testFullscreenBrowserContentWindowIsNotExcludedByFrameShape() {
        XCTAssertFalse(
            ScreenRecorder.isLikelyAuxiliaryWindowFrame(
                CGRect(x: 0, y: 0, width: 1470, height: 923)
            )
        )
    }

    func testNormalWideDocumentWindowIsNotExcludedByFrameShape() {
        XCTAssertFalse(
            ScreenRecorder.isLikelyAuxiliaryWindowFrame(
                CGRect(x: 0, y: 0, width: 1400, height: 500)
            )
        )
    }

    func testFullscreenBrowserViewportWithBottomAnchoredFrameIsNotShifted() {
        let adjusted = CaptureSizePolicy.adjustedWindowViewportForFullscreenBrowserCapture(
            CGRect(x: 53, y: 0, width: 1470, height: 835),
            screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
            bundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(adjusted.minX, 53, accuracy: 0.0001)
        XCTAssertEqual(adjusted.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(adjusted.width, 1470, accuracy: 0.0001)
        XCTAssertEqual(adjusted.height, 835, accuracy: 0.0001)
    }

    func testFullscreenBrowserViewportAdjustmentDoesNotAffectNonBrowsers() {
        let viewport = CGRect(x: 151, y: 99, width: 1168, height: 780)
        let adjusted = CaptureSizePolicy.adjustedWindowViewportForFullscreenBrowserCapture(
            viewport,
            screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
            bundleIdentifier: "com.apple.dt.Xcode"
        )

        XCTAssertEqual(adjusted, viewport)
    }

    func testFullscreenBrowserViewportAdjustmentDoesNotAffectSmallWindows() {
        let viewport = CGRect(x: 300, y: 120, width: 700, height: 520)
        let adjusted = CaptureSizePolicy.adjustedWindowViewportForFullscreenBrowserCapture(
            viewport,
            screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
            bundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(adjusted, viewport)
    }

    func testBrowserBundleIdentifierRecognizesCommonBrowsers() {
        XCTAssertTrue(CaptureSizePolicy.isBrowserBundleIdentifier("com.google.Chrome"))
        XCTAssertTrue(CaptureSizePolicy.isBrowserBundleIdentifier("com.apple.Safari"))
        XCTAssertTrue(CaptureSizePolicy.isBrowserBundleIdentifier("com.microsoft.edgemac"))
        XCTAssertTrue(CaptureSizePolicy.isBrowserBundleIdentifier("company.thebrowser.Browser"))
        XCTAssertTrue(CaptureSizePolicy.isBrowserBundleIdentifier("com.brave.Browser"))
        XCTAssertTrue(CaptureSizePolicy.isBrowserBundleIdentifier("org.mozilla.firefox"))
        XCTAssertFalse(CaptureSizePolicy.isBrowserBundleIdentifier("com.apple.dt.Xcode"))
    }

}
