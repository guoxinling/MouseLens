import CoreGraphics
import XCTest
@testable import MouseLens

final class SourceCropPlannerTests: XCTestCase {
    func testBaseCropKeepsRequestedAspectRatioCentered() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let crop = planner.baseCropRect(for: source, outputAspectRatio: 9.0 / 16.0)

        XCTAssertEqual(crop.width / crop.height, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(crop.midX, source.midX, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, source.midY, accuracy: 0.0001)
    }

    func testFocusedCropStaysInsideSourceBounds() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshot = FrameSnapshot(
            focus: .init(x: 0.98, y: 0.02),
            zoom: 1.6
        )

        let crop = planner.cropRect(
            for: source,
            outputAspectRatio: 16.0 / 9.0,
            snapshot: snapshot
        )

        XCTAssertGreaterThanOrEqual(crop.minX, source.minX)
        XCTAssertGreaterThanOrEqual(crop.minY, source.minY)
        XCTAssertLessThanOrEqual(crop.maxX, source.maxX)
        XCTAssertLessThanOrEqual(crop.maxY, source.maxY)
        XCTAssertLessThan(crop.width, source.width)
        XCTAssertLessThan(crop.height, source.height)
    }

    func testRenderLayoutUsesPaddingToInsetContentRect() {
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0.1)

        XCTAssertEqual(layout.contentRect.minX, 108, accuracy: 0.0001)
        XCTAssertEqual(layout.contentRect.minY, 108, accuracy: 0.0001)
        XCTAssertEqual(layout.contentRect.width, 1704, accuracy: 0.0001)
        XCTAssertEqual(layout.contentRect.height, 864, accuracy: 0.0001)
    }
}
