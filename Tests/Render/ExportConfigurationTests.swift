import AVFoundation
import XCTest
@testable import MouseLens

final class ExportConfigurationTests: XCTestCase {
    func testRecommendedMP4Uses1080pThirtyFPSAndHighQuality() {
        let configuration = ExportConfiguration.recommended(for: .landscape)

        XCTAssertEqual(configuration.format, .mp4)
        XCTAssertEqual(configuration.resolution, .p1080)
        XCTAssertEqual(configuration.frameRate, .fps30)
        XCTAssertEqual(configuration.quality, .high)
        XCTAssertTrue(configuration.includesCursor)
        XCTAssertTrue(configuration.includesClickFeedback)
    }

    func testGIFIsAvailableAndUsesApprovedDefaults() {
        let configuration = ExportConfiguration.recommended(
            for: .landscape,
            format: .gif
        )

        XCTAssertTrue(ExportFormat.gif.isAvailable)
        XCTAssertEqual(configuration.format, .gif)
        XCTAssertEqual(configuration.resolution, .p720)
        XCTAssertEqual(configuration.frameRate, .fps15)
        XCTAssertEqual(configuration.quality, .balanced)
        XCTAssertTrue(configuration.includesCursor)
        XCTAssertTrue(configuration.includesClickFeedback)
    }

    func testGIFAllowedResolutionsMatchReleaseScope() {
        XCTAssertEqual(
            ExportConfiguration.allowedResolutions(for: .gif),
            [.p720, .p1080]
        )
    }

    func testGIFFixedFrameRateIsFifteenFPS() {
        XCTAssertEqual(
            ExportConfiguration.allowedFrameRates(for: .gif),
            [.fps15]
        )
    }

    func testGIFEstimateIncreasesWithResolution() {
        let low = ExportConfiguration.recommended(for: .landscape, format: .gif)
        var high = low
        high.resolution = .p1080

        XCTAssertGreaterThan(
            ExportSizeEstimator.estimatedByteCount(for: high, aspectRatio: .landscape, duration: 8),
            ExportSizeEstimator.estimatedByteCount(for: low, aspectRatio: .landscape, duration: 8)
        )
    }

    func testGIFEstimateTreatsPortraitAndLandscape1080pAsSameResolutionClass() {
        var landscape = ExportConfiguration.recommended(for: .landscape, format: .gif)
        landscape.resolution = .p1080

        var portrait = ExportConfiguration.recommended(for: .portrait, format: .gif)
        portrait.resolution = .p1080

        XCTAssertEqual(
            ExportSizeEstimator.estimatedByteCount(for: landscape, aspectRatio: .landscape, duration: 8),
            ExportSizeEstimator.estimatedByteCount(for: portrait, aspectRatio: .portrait, duration: 8)
        )
    }

    func testInvalidGIFSettingsAreNormalizedToReleaseScope() {
        var configuration = ExportConfiguration(
            format: .gif,
            resolution: .p2160,
            frameRate: .fps60,
            quality: .small,
            includesCursor: false,
            includesClickFeedback: false
        )

        XCTAssertEqual(configuration.resolution, .p720)
        XCTAssertEqual(configuration.frameRate, .fps15)
        XCTAssertEqual(configuration.quality, .balanced)
        XCTAssertTrue(configuration.includesCursor)
        XCTAssertTrue(configuration.includesClickFeedback)

        configuration.resolution = .p1440
        configuration.frameRate = .fps30
        configuration.quality = .high
        configuration.includesCursor = false
        configuration.includesClickFeedback = false

        XCTAssertEqual(configuration.resolution, .p720)
        XCTAssertEqual(configuration.frameRate, .fps15)
        XCTAssertEqual(configuration.quality, .balanced)
        XCTAssertTrue(configuration.includesCursor)
        XCTAssertTrue(configuration.includesClickFeedback)
    }

    func testResolutionPreservesProjectAspect() {
        XCTAssertEqual(
            ExportResolution.p720.renderSize(for: .landscape),
            CGSize(width: 1280, height: 720)
        )
        XCTAssertEqual(
            ExportResolution.p1440.renderSize(for: .landscape),
            CGSize(width: 2560, height: 1440)
        )
        XCTAssertEqual(
            ExportResolution.p2160.renderSize(for: .landscape),
            CGSize(width: 3840, height: 2160)
        )
        XCTAssertEqual(
            ExportResolution.p720.renderSize(for: .portrait),
            CGSize(width: 720, height: 1280)
        )
        XCTAssertEqual(
            ExportResolution.p1440.renderSize(for: .portrait),
            CGSize(width: 1440, height: 2560)
        )
        XCTAssertEqual(
            ExportResolution.p2160.renderSize(for: .portrait),
            CGSize(width: 2160, height: 3840)
        )
        XCTAssertEqual(
            ExportResolution.p720.renderSize(for: .square),
            CGSize(width: 720, height: 720)
        )
        XCTAssertEqual(
            ExportResolution.p1440.renderSize(for: .square),
            CGSize(width: 1440, height: 1440)
        )
        XCTAssertEqual(
            ExportResolution.p2160.renderSize(for: .square),
            CGSize(width: 2160, height: 2160)
        )
    }

    func testBitrateScalesDownForSmallerAndLowerQualityExports() {
        let high1080 = ExportQuality.high.averageBitRate(
            renderSize: CGSize(width: 1920, height: 1080),
            frameRate: .fps30
        )
        let small720 = ExportQuality.small.averageBitRate(
            renderSize: CGSize(width: 1280, height: 720),
            frameRate: .fps15
        )

        XCTAssertGreaterThan(high1080, small720)
        XCTAssertGreaterThan(small720, 0)
    }

    func testHighQuality1080pThirtyFPSUsesTwentyMegabits() {
        let high1080 = ExportQuality.high.averageBitRate(
            renderSize: CGSize(width: 1920, height: 1080),
            frameRate: .fps30
        )

        XCTAssertEqual(high1080, 20_000_000)
    }

    func testHighQuality1080pSixtyFPSUsesTwentyEightMegabits() {
        let high1080 = ExportQuality.high.averageBitRate(
            renderSize: CGSize(width: 1920, height: 1080),
            frameRate: .fps60
        )

        XCTAssertEqual(high1080, 28_000_000)
    }

    func testHighQuality4KSixtyFPSUsesFiftyFiveMegabits() {
        let high4K = ExportQuality.high.averageBitRate(
            renderSize: CGSize(width: 3840, height: 2160),
            frameRate: .fps60
        )

        XCTAssertEqual(high4K, 55_000_000)
    }

    func testEstimatedExportSizeStaysBelowStrictBitrateUpperBound() {
        let configuration = ExportConfiguration(
            format: .mp4,
            resolution: .p1080,
            frameRate: .fps60,
            quality: .high,
            includesCursor: true,
            includesClickFeedback: true
        )
        let duration = 13.0
        let renderSize = configuration.renderSize(for: .landscape)
        let strictUpperBound = Int64(
            Double(
                configuration.quality.averageBitRate(
                    renderSize: renderSize,
                    frameRate: configuration.frameRate
                ) + 192_000
            ) * duration / 8.0
        )

        let estimate = ExportSizeEstimator.estimatedByteCount(
            for: configuration,
            aspectRatio: .landscape,
            duration: duration
        )

        XCTAssertGreaterThan(estimate, 0)
        XCTAssertLessThan(estimate, strictUpperBound)
    }

    func testEstimatedExportSizeIncreasesWithResolution() {
        let duration = 20.0
        let low = ExportConfiguration(
            format: .mp4,
            resolution: .p1440,
            frameRate: .fps30,
            quality: .high,
            includesCursor: true,
            includesClickFeedback: true
        )
        let high = ExportConfiguration(
            format: .mp4,
            resolution: .p2160,
            frameRate: .fps30,
            quality: .high,
            includesCursor: true,
            includesClickFeedback: true
        )

        XCTAssertGreaterThan(
            ExportSizeEstimator.estimatedByteCount(for: high, aspectRatio: .landscape, duration: duration),
            ExportSizeEstimator.estimatedByteCount(for: low, aspectRatio: .landscape, duration: duration)
        )
    }

    func testEstimatedExportSizeIncreasesWithFrameRate() {
        let duration = 20.0
        let low = ExportConfiguration(
            format: .mp4,
            resolution: .p1080,
            frameRate: .fps30,
            quality: .high,
            includesCursor: true,
            includesClickFeedback: true
        )
        let high = ExportConfiguration(
            format: .mp4,
            resolution: .p1080,
            frameRate: .fps60,
            quality: .high,
            includesCursor: true,
            includesClickFeedback: true
        )

        XCTAssertGreaterThan(
            ExportSizeEstimator.estimatedByteCount(for: high, aspectRatio: .landscape, duration: duration),
            ExportSizeEstimator.estimatedByteCount(for: low, aspectRatio: .landscape, duration: duration)
        )
    }

    func testVideoOutputSettingsDeclareColorMetadata() {
        let settings = VideoExportSettingsBuilder.makeOutputSettings(
            renderSize: CGSize(width: 1920, height: 1080),
            averageBitRate: 20_000_000
        )

        let colorProperties = settings[AVVideoColorPropertiesKey] as? [String: Any]

        XCTAssertEqual(colorProperties?[AVVideoColorPrimariesKey] as? String, AVVideoColorPrimaries_ITU_R_709_2)
        XCTAssertEqual(colorProperties?[AVVideoTransferFunctionKey] as? String, AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(colorProperties?[AVVideoYCbCrMatrixKey] as? String, AVVideoYCbCrMatrix_ITU_R_709_2)
    }

    func testSingleAudioTrackUsesPassthroughMuxStrategy() {
        XCTAssertEqual(
            FinalAudioMuxStrategy.forSourceAudioTrackCount(1),
            .passthroughSingleTrack
        )
    }

    func testMultipleAudioTracksUseReencodeMuxStrategy() {
        XCTAssertEqual(
            FinalAudioMuxStrategy.forSourceAudioTrackCount(2),
            .reencodeForMixdown
        )
    }

}
