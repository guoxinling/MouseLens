import XCTest
@testable import MouseLens
import CoreGraphics

final class BackgroundRenderResolverTests: XCTestCase {
    func testGradientPresetBuildsSwiftUIPreviewGradient() {
        let preset = BackgroundPresetCatalog.preset(id: "aurora-air")
        let preview = BackgroundPreviewStyle.makeGradient(for: preset)

        XCTAssertNotNil(preview)
    }

    func testWallpaperPresetLooksUpAssetName() {
        let preset = BackgroundPresetCatalog.preset(id: "soft-glass")

        XCTAssertEqual(BackgroundRenderResolver.wallpaperAssetName(for: preset), "BackgroundSoftGlass")
    }

    func testRenderResolverUsesCatalogColorsForGradientPreset() {
        let preset = BackgroundPresetCatalog.preset(id: "midnight-pulse")
        let colors = BackgroundRenderResolver.gradientColors(for: preset)

        XCTAssertEqual(colors.count, 3)
        XCTAssertEqual(colors[0].red, 0.05, accuracy: 0.0001)
    }
}

private extension CGColor {
    var red: CGFloat {
        guard let components = components,
              components.count >= 3 else {
            return 0
        }

        return components[0]
    }
}
