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
}
