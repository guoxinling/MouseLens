import AVFoundation
import CoreGraphics
import XCTest
@testable import MouseLens

final class CaptureSizePolicyTests: XCTestCase {
    func testRetainsNativeRetinaSizeWhenWithin3840Ceiling() {
        let size = CaptureSizePolicy.recommendedCaptureSize(
            contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
            pointPixelScale: 2
        )

        XCTAssertEqual(size.width, 2880, accuracy: 0.0001)
        XCTAssertEqual(size.height, 1800, accuracy: 0.0001)
    }

    func testScalesDownOnlyWhenRawCaptureExceeds3840Ceiling() {
        let size = CaptureSizePolicy.recommendedCaptureSize(
            contentRect: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            pointPixelScale: 2
        )

        XCTAssertEqual(size.width, 3840, accuracy: 0.0001)
        XCTAssertEqual(size.height, 2160, accuracy: 0.0001)
    }

    func testWindowCaptureSizeUsesFilterContentRectInsteadOfWindowFrame() {
        let size = CaptureSizePolicy.recommendedWindowCaptureSize(
            windowFrame: CGRect(x: 0, y: 0, width: 3024, height: 1964),
            filterContentRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
            pointPixelScale: 2
        )

        XCTAssertEqual(size.width, 3024, accuracy: 0.0001)
        XCTAssertEqual(size.height, 1964, accuracy: 0.0001)
    }

    func testRecordingFrameTransformScalesSourceIntoWriterCanvas() {
        let transform = CaptureSizePolicy.recordingFrameTransform(
            sourceExtent: CGRect(x: 0, y: 0, width: 1512, height: 982),
            destinationSize: CGSize(width: 3024, height: 1964)
        )

        let mappedRect = CGRect(x: 0, y: 0, width: 1512, height: 982).applying(transform)

        XCTAssertEqual(mappedRect.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(mappedRect.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(mappedRect.width, 3024, accuracy: 0.0001)
        XCTAssertEqual(mappedRect.height, 1964, accuracy: 0.0001)
    }

    func testRecordingFrameTransformCropsVisibleWindowSourceIntoWriterCanvas() {
        let transform = CaptureSizePolicy.recordingFrameTransform(
            sourceExtent: CGRect(x: 0, y: 0, width: 2660, height: 1670),
            destinationSize: CGSize(width: 2940, height: 1670)
        )

        let mappedVisibleRect = CGRect(x: 0, y: 0, width: 2660, height: 1670).applying(transform)

        XCTAssertEqual(mappedVisibleRect.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(mappedVisibleRect.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(mappedVisibleRect.width, 2940, accuracy: 0.0001)
        XCTAssertEqual(mappedVisibleRect.height, 1670, accuracy: 0.0001)
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

    func testFullscreenBrowserPointerViewportUsesFullScreenVerticalDomain() {
        let viewport = CaptureSizePolicy.pointerViewportForWindowCapture(
            appKitViewport: CGRect(x: 0, y: 0, width: 1470, height: 835),
            filterContentRect: CGRect(x: 0, y: 121, width: 1470, height: 835),
            screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
            bundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(viewport.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(viewport.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(viewport.width, 1470, accuracy: 0.0001)
        XCTAssertEqual(viewport.height, 956, accuracy: 0.0001)
    }

    func testPointerViewportKeepsAppKitViewportForNonBrowserWindow() {
        let appKitViewport = CGRect(x: 20, y: 30, width: 1200, height: 800)
        let viewport = CaptureSizePolicy.pointerViewportForWindowCapture(
            appKitViewport: appKitViewport,
            filterContentRect: CGRect(x: 0, y: 121, width: 1470, height: 835),
            screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
            bundleIdentifier: "com.apple.dt.Xcode"
        )

        XCTAssertEqual(viewport, appKitViewport)
    }

    func testFullscreenBrowserViewportDoesNotTreatShortHeightAsTopGap() {
        let adjusted = CaptureSizePolicy.adjustedWindowViewportForFullscreenBrowserCapture(
            CGRect(x: 0, y: 0, width: 1329.5, height: 835),
            screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
            bundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(adjusted.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(adjusted.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(adjusted.width, 1329.5, accuracy: 0.0001)
        XCTAssertEqual(adjusted.height, 835, accuracy: 0.0001)
    }

    func testWindowViewportIgnoresDetectedVisibleSourceSizeForPointerCoordinates() {
        let original = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1470, height: 835)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1470, height: 956))
        )

        let adjusted = CaptureSizePolicy.adjustedCoordinateSpaceForVisibleWindowSource(
            original,
            sourceSize: CGSize(width: 2940, height: 1670),
            visibleSourceRect: CGRect(x: 0, y: 0, width: 2660, height: 1670)
        )

        XCTAssertEqual(adjusted.viewport.rect.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(adjusted.viewport.rect.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(adjusted.viewport.rect.width, 1470, accuracy: 0.0001)
        XCTAssertEqual(adjusted.viewport.rect.height, 835, accuracy: 0.0001)
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

    func testFirstAudioSampleAlignsToVideoSessionStart() {
        let sessionStart = CMTime(seconds: 10.0, preferredTimescale: 600)
        let firstAudio = CMTime(seconds: 10.35, preferredTimescale: 600)

        let presentationTime = CaptureAudioRetiming.presentationTime(
            samplePTS: firstAudio,
            sessionStartPTS: sessionStart,
            accumulatedPauseDuration: .zero,
            firstAudioPTS: firstAudio
        )

        XCTAssertEqual(presentationTime?.seconds ?? -1, 0, accuracy: 0.0001)
    }

    func testLaterAudioSamplesKeepTheirDistanceFromFirstAudioSample() {
        let sessionStart = CMTime(seconds: 10.0, preferredTimescale: 600)
        let firstAudio = CMTime(seconds: 10.35, preferredTimescale: 600)
        let laterAudio = CMTime(seconds: 12.10, preferredTimescale: 600)

        let presentationTime = CaptureAudioRetiming.presentationTime(
            samplePTS: laterAudio,
            sessionStartPTS: sessionStart,
            accumulatedPauseDuration: .zero,
            firstAudioPTS: firstAudio
        )

        XCTAssertEqual(presentationTime?.seconds ?? -1, 1.75, accuracy: 0.0001)
    }
}
