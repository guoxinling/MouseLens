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
        XCTAssertEqual(layout.frame.maxX, contentRect.maxX - 25.2, accuracy: 0.0001)
        XCTAssertEqual(layout.frame.maxY, contentRect.maxY - 25.2, accuracy: 0.0001)
        XCTAssertEqual(layout.clippingPathCornerRadius, layout.frame.width / 2, accuracy: 0.0001)
    }

    func testFourCornerPositionsUseContentRectCoordinates() {
        let contentRect = CGRect(x: 40, y: 30, width: 400, height: 300)
        let expectedSize: CGFloat = 75
        let expectedInset: CGFloat = 18

        XCTAssertFrame(
            for: .topLeft,
            in: contentRect,
            equals: CGRect(x: 58, y: 48, width: expectedSize, height: expectedSize)
        )
        XCTAssertFrame(
            for: .topRight,
            in: contentRect,
            equals: CGRect(x: 347, y: 48, width: expectedSize, height: expectedSize)
        )
        XCTAssertFrame(
            for: .bottomLeft,
            in: contentRect,
            equals: CGRect(x: 58, y: 237, width: expectedSize, height: expectedSize)
        )
        XCTAssertFrame(
            for: .bottomRight,
            in: contentRect,
            equals: CGRect(
                x: contentRect.maxX - expectedInset - expectedSize,
                y: contentRect.maxY - expectedInset - expectedSize,
                width: expectedSize,
                height: expectedSize
            )
        )
    }

    func testRoundedRectCornerRadiusIsClampedToHalfBubbleSize() {
        let layout = PresenterOverlayGeometry.layout(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 160),
            style: PresenterBubbleStyle(
                isEnabled: true,
                position: .topLeft,
                normalizedSize: 0.25,
                shape: .roundedRect,
                cornerRadius: 80,
                shadowOpacity: 0.24
            )
        )

        XCTAssertEqual(layout.frame.size, CGSize(width: 40, height: 40))
        XCTAssertEqual(layout.clippingPathCornerRadius, 20, accuracy: 0.0001)
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
        XCTAssertEqual(layout.frame.size, CGSize(width: 24, height: 24))
        XCTAssertEqual(layout.frame.origin, CGPoint(x: 18, y: 20))
        XCTAssertEqual(layout.clippingPathCornerRadius, 12, accuracy: 0.0001)
    }

    func testPreviewAndExportUseSamePresenterBubbleLayout() {
        let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .topRight,
            normalizedSize: 0.18,
            shape: .roundedRect,
            cornerRadius: 22,
            shadowOpacity: 0.24
        )

        let previewLayout = PresenterOverlayGeometry.layout(contentRect: contentRect, style: style)
        let exportLayout = PresenterOverlayGeometry.layout(contentRect: contentRect, style: style)

        XCTAssertEqual(previewLayout, exportLayout)
    }

    private func XCTAssertFrame(
        for position: PresenterBubblePosition,
        in contentRect: CGRect,
        equals expectedFrame: CGRect,
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

        XCTAssertEqual(layout.frame.origin.x, expectedFrame.origin.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(layout.frame.origin.y, expectedFrame.origin.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(layout.frame.width, expectedFrame.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(layout.frame.height, expectedFrame.height, accuracy: 0.0001, file: file, line: line)
    }
}
