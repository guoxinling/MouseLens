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

    func testResolutionPreservesProjectAspect() {
        XCTAssertEqual(
            ExportResolution.p720.renderSize(for: .landscape),
            CGSize(width: 1280, height: 720)
        )
        XCTAssertEqual(
            ExportResolution.p720.renderSize(for: .portrait),
            CGSize(width: 720, height: 1280)
        )
        XCTAssertEqual(
            ExportResolution.p720.renderSize(for: .square),
            CGSize(width: 720, height: 720)
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

    func testGIFIsVisibleButUnavailableUntilEncoderLands() {
        XCTAssertFalse(ExportFormat.gif.isAvailable)
        XCTAssertTrue(ExportFormat.mp4.isAvailable)
    }
}
