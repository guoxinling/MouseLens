import CoreGraphics
import XCTest
@testable import MouseLens

final class PresenterOverlayGeometryTests: XCTestCase {
    func testBottomRightCircleBubbleStaysInsideContentRect() {
        let contentRect = CGRect(x: 100, y: 80, width: 1280, height: 720)

        let layout = PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                position: .bottomRight,
                normalizedSize: 0.22,
                shape: .circle,
                cornerRadius: 18,
                shadowOpacity: 0.24
            )
        )

        XCTAssertTrue(contentRect.contains(layout.frame))
        XCTAssertEqual(layout.frame.width, 158.4, accuracy: 0.0001)
        XCTAssertEqual(layout.frame.height, 158.4, accuracy: 0.0001)
        XCTAssertGreaterThan(layout.frame.midX, contentRect.midX)
        XCTAssertGreaterThan(layout.frame.midY, contentRect.midY)
        XCTAssertEqual(layout.clippingPathCornerRadius, layout.frame.width / 2, accuracy: 0.0001)
    }

    func testFourCornerPositionsUseContentRectCoordinates() {
        let contentRect = CGRect(x: 40, y: 30, width: 400, height: 300)

        XCTAssertFrame(for: .topLeft, in: contentRect, isLeft: true, isTop: true)
        XCTAssertFrame(for: .topRight, in: contentRect, isLeft: false, isTop: true)
        XCTAssertFrame(for: .bottomLeft, in: contentRect, isLeft: true, isTop: false)
        XCTAssertFrame(for: .bottomRight, in: contentRect, isLeft: false, isTop: false)
    }

    func testRoundedRectCornerRadiusIsClampedToHalfBubbleSize() {
        let layout = PresenterOverlayGeometry.layout(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 160),
            style: PresenterBubbleStyle(
                isEnabled: true,
                normalizedCenter: NormalizedPoint(x: 0.2, y: 0.2),
                normalizedSize: 0.25,
                cornerRadiusRatio: 0.5,
                shadowOpacity: 0.24
            )
        )

        XCTAssertEqual(layout.frame.size, CGSize(width: 40, height: 40))
        XCTAssertEqual(layout.clippingPathCornerRadius, 20, accuracy: 0.0001)
    }

    func testFreePositionBubbleCentersOnNormalizedPoint() {
        let contentRect = CGRect(x: 100, y: 80, width: 800, height: 600)

        let layout = PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                normalizedCenter: NormalizedPoint(x: 0.5, y: 0.25),
                normalizedSize: 0.2,
                cornerRadiusRatio: 0.25,
                shadowOpacity: 0.24
            )
        )

        XCTAssertEqual(layout.frame.size, CGSize(width: 120, height: 120))
        XCTAssertEqual(layout.frame.midX, 500, accuracy: 0.0001)
        XCTAssertEqual(layout.frame.midY, 230, accuracy: 0.0001)
        XCTAssertEqual(layout.clippingPathCornerRadius, 30, accuracy: 0.0001)
    }

    func testFreePositionBubbleIsClampedInsideContentRect() {
        let contentRect = CGRect(x: 100, y: 80, width: 800, height: 600)

        let layout = PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                normalizedCenter: NormalizedPoint(x: 0, y: 1),
                normalizedSize: 0.2,
                cornerRadiusRatio: 0,
                shadowOpacity: 0.24
            )
        )

        XCTAssertEqual(layout.frame.minX, contentRect.minX, accuracy: 0.0001)
        XCTAssertEqual(layout.frame.maxY, contentRect.maxY, accuracy: 0.0001)
        XCTAssertEqual(layout.clippingPathCornerRadius, 0, accuracy: 0.0001)
    }

    func testCornerPresetsPlaceBubbleAgainstContentEdges() {
        let contentRect = CGRect(x: 100, y: 80, width: 800, height: 600)

        let topLeft = layout(for: .topLeft, in: contentRect)
        XCTAssertEqual(topLeft.frame.minX, contentRect.minX, accuracy: 0.0001)
        XCTAssertEqual(topLeft.frame.minY, contentRect.minY, accuracy: 0.0001)

        let topRight = layout(for: .topRight, in: contentRect)
        XCTAssertEqual(topRight.frame.maxX, contentRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(topRight.frame.minY, contentRect.minY, accuracy: 0.0001)

        let bottomLeft = layout(for: .bottomLeft, in: contentRect)
        XCTAssertEqual(bottomLeft.frame.minX, contentRect.minX, accuracy: 0.0001)
        XCTAssertEqual(bottomLeft.frame.maxY, contentRect.maxY, accuracy: 0.0001)

        let bottomRight = layout(for: .bottomRight, in: contentRect)
        XCTAssertEqual(bottomRight.frame.maxX, contentRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.frame.maxY, contentRect.maxY, accuracy: 0.0001)
    }

    func testFreePositionAtContentEdgeUsesEdgeAnchorInsteadOfClampingCenterInward() {
        let contentRect = CGRect(x: 100, y: 80, width: 800, height: 600)

        let layout = PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                normalizedCenter: NormalizedPoint(x: 1, y: 1),
                normalizedSize: 0.2,
                cornerRadiusRatio: 0.5,
                shadowOpacity: 0.24
            )
        )

        XCTAssertEqual(layout.frame.maxX, contentRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(layout.frame.maxY, contentRect.maxY, accuracy: 0.0001)
    }

    func testDisabledStyleReturnsNoOverlayFrame() {
        let layout = PresenterOverlayGeometry.layout(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            style: PresenterBubbleStyle.defaultValue
        )

        XCTAssertEqual(layout, PresenterOverlayLayout(frame: .zero, clippingPathCornerRadius: 0))
    }

    func testBubbleSizeAndInsetAreClampedForTinyContentRect() {
        let contentRect = CGRect(x: 10, y: 20, width: 32, height: 24)

        let layout = PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                position: .bottomRight,
                normalizedSize: 2,
                shape: .circle,
                cornerRadius: 18,
                shadowOpacity: 0.24
            )
        )

        XCTAssertTrue(contentRect.contains(layout.frame))
        XCTAssertEqual(layout.frame.size, CGSize(width: 12, height: 12))
        XCTAssertEqual(layout.frame.origin, CGPoint(x: 30, y: 32))
        XCTAssertEqual(layout.clippingPathCornerRadius, 6, accuracy: 0.0001)
    }

    func testPreviewAndExportUseSamePresenterBubbleLayout() {
        let videoDisplayRect = CGRect(x: 240, y: 0, width: 1440, height: 1080)
        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .topRight,
            normalizedSize: 0.18,
            shape: .roundedRect,
            cornerRadius: 22,
            shadowOpacity: 0.24
        )

        let previewLayout = PresenterOverlayGeometry.layout(contentRect: videoDisplayRect, style: style)
        let exportLayout = PresenterOverlayGeometry.layout(contentRect: videoDisplayRect, style: style)

        XCTAssertEqual(previewLayout, exportLayout)
    }

    func testPresenterBubbleAnchorsToStableCanvasWhenWindowSourceIsFitted() {
        let stableCanvasRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let fittedWindowRect = CGRect(x: 350, y: 0, width: 900, height: 900)
        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .bottomRight,
            normalizedSize: 0.2,
            shape: .circle,
            cornerRadius: 0,
            shadowOpacity: 0.24
        )

        let anchoredToCanvas = PresenterOverlayGeometry.layout(contentRect: stableCanvasRect, style: style)
        let anchoredToVideo = PresenterOverlayGeometry.layout(contentRect: fittedWindowRect, style: style)

        XCTAssertEqual(anchoredToCanvas.frame.maxX, stableCanvasRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(anchoredToCanvas.frame.maxY, stableCanvasRect.maxY, accuracy: 0.0001)
        XCTAssertGreaterThan(anchoredToCanvas.frame.maxX, anchoredToVideo.frame.maxX)
    }

    func testPresenterBubbleUsesStableCanvasIndependentOfVideoPadding() {
        let stableCanvasRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let paddedVideoRect = CGRect(x: 120, y: 80, width: 1360, height: 740)
        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .bottomRight,
            normalizedSize: 0.2,
            shape: .circle,
            cornerRadius: 0,
            shadowOpacity: 0.24
        )

        let anchoredToCanvas = PresenterOverlayGeometry.layout(contentRect: stableCanvasRect, style: style)
        let anchoredToPaddedVideo = PresenterOverlayGeometry.layout(contentRect: paddedVideoRect, style: style)

        XCTAssertEqual(anchoredToCanvas.frame.maxX, stableCanvasRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(anchoredToCanvas.frame.maxY, stableCanvasRect.maxY, accuracy: 0.0001)
        XCTAssertGreaterThan(anchoredToCanvas.frame.maxX, anchoredToPaddedVideo.frame.maxX)
        XCTAssertGreaterThan(anchoredToCanvas.frame.maxY, anchoredToPaddedVideo.frame.maxY)
    }

    private func XCTAssertFrame(
        for position: PresenterBubblePosition,
        in contentRect: CGRect,
        isLeft: Bool,
        isTop: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let layout = PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                position: position,
                normalizedSize: 0.25,
                shape: .circle,
                cornerRadius: 18,
                shadowOpacity: 0.24
            )
        )

        XCTAssertTrue(contentRect.contains(layout.frame), file: file, line: line)
        XCTAssertEqual(layout.frame.size, CGSize(width: 75, height: 75), file: file, line: line)
        if isLeft {
            XCTAssertLessThan(layout.frame.midX, contentRect.midX, file: file, line: line)
        } else {
            XCTAssertGreaterThan(layout.frame.midX, contentRect.midX, file: file, line: line)
        }
        if isTop {
            XCTAssertLessThan(layout.frame.midY, contentRect.midY, file: file, line: line)
        } else {
            XCTAssertGreaterThan(layout.frame.midY, contentRect.midY, file: file, line: line)
        }
    }

    private func layout(
        for position: PresenterBubblePosition,
        in contentRect: CGRect
    ) -> PresenterOverlayLayout {
        PresenterOverlayGeometry.layout(
            contentRect: contentRect,
            style: PresenterBubbleStyle(
                isEnabled: true,
                position: position,
                normalizedSize: 0.2,
                shape: .circle,
                cornerRadius: 18,
                shadowOpacity: 0.24
            )
        )
    }
}
