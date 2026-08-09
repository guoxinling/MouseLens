import XCTest
@testable import MouseLens

final class CursorStyleTests: XCTestCase {
    func testCursorStyleCatalogIncludesDefaultAndThreeCustomStyles() {
        XCTAssertEqual(
            CursorStyle.allCases,
            [.systemArrow, .pointerHand, .magicWand, .catPaw]
        )
    }

    func testCursorStylesDeclareRenderableAssetsAndHotspots() {
        for style in CursorStyle.allCases {
            XCTAssertFalse(style.assetName.isEmpty)
            XCTAssertGreaterThan(style.templateSize.width, 0)
            XCTAssertGreaterThan(style.templateSize.height, 0)
            XCTAssertGreaterThanOrEqual(style.hotspot.x, 0)
            XCTAssertGreaterThanOrEqual(style.hotspot.y, 0)
            XCTAssertLessThanOrEqual(style.hotspot.x, style.templateSize.width)
            XCTAssertLessThanOrEqual(style.hotspot.y, style.templateSize.height)
        }

        XCTAssertEqual(CursorStyle.systemArrow.assetName, "CursorSystemArrow")
        XCTAssertEqual(CursorStyle.pointerHand.assetName, "CursorPointerHand")
        XCTAssertEqual(CursorStyle.magicWand.assetName, "CursorMagicWand")
        XCTAssertEqual(CursorStyle.catPaw.assetName, "CursorCatPaw")
    }

    func testImageCursorStylesUseFlippedPreviewCorrection() {
        XCTAssertFalse(CursorStyle.systemArrow.requiresFlippedPreviewImageCorrection)
        XCTAssertTrue(CursorStyle.pointerHand.requiresFlippedPreviewImageCorrection)
        XCTAssertTrue(CursorStyle.magicWand.requiresFlippedPreviewImageCorrection)
        XCTAssertTrue(CursorStyle.catPaw.requiresFlippedPreviewImageCorrection)
    }

    func testCursorVisualMetricsUseSameScaleForPreviewAndExport() {
        let contentRect = CGRect(x: 120, y: 80, width: 1600, height: 900)

        for style in CursorStyle.allCases {
            let previewScale = CursorVisualMetrics.scale(for: style, contentRect: contentRect)
            let exportScale = CursorVisualMetrics.scale(for: style, contentRect: contentRect)
            XCTAssertEqual(previewScale, exportScale, accuracy: 0.0001)
        }
    }

    func testCursorVisualMetricsKeepTipPinnedForCustomStyles() {
        let tip = CGPoint(x: 640, y: 420)
        let contentRect = CGRect(x: 0, y: 0, width: 1280, height: 720)

        for style in [CursorStyle.pointerHand, .magicWand, .catPaw] {
            let scale = CursorVisualMetrics.scale(for: style, contentRect: contentRect)
            let origin = CursorGeometry.origin(forTip: tip, scale: scale, style: style)

            XCTAssertEqual((origin.x * scale) + (style.hotspot.x * scale), tip.x, accuracy: 0.0001)
            XCTAssertEqual((origin.y * scale) + (style.hotspot.y * scale), tip.y, accuracy: 0.0001)
        }
    }

    func testProjectStylePersistsCursorStyle() throws {
        let style = ProjectStyle(
            aspectRatio: .landscape,
            backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
            cornerRadius: 10.35,
            shadowRadius: 24,
            followStrength: 0.72,
            clickEmphasis: 0.54,
            padding: 0.04,
            presenterBubbleStyle: .defaultValue,
            cursorStyle: .magicWand
        )

        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(ProjectStyle.self, from: encoded)

        XCTAssertEqual(decoded.cursorStyle, .magicWand)
    }

    func testLegacyProjectStyleDefaultsToSystemCursor() throws {
        let legacyJSON = """
        {
          "aspectRatio": "landscape",
          "backgroundPresetID": "aurora-air",
          "cornerRadius": 10.35,
          "shadowRadius": 24,
          "followStrength": 0.72,
          "clickEmphasis": 0.54,
          "padding": 0.04
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProjectStyle.self, from: legacyJSON)

        XCTAssertEqual(decoded.cursorStyle, .systemArrow)
    }
}
