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
}
