import XCTest
@testable import MouseLens
import CoreGraphics

final class BackgroundRenderResolverTests: XCTestCase {
    func testWallpaperPresetLooksUpAssetName() {
        let preset = BackgroundPresetCatalog.preset(id: "soft-glass")

        XCTAssertEqual(BackgroundRenderResolver.wallpaperAssetName(for: preset), "BackgroundSoftGlass")
    }

    func testAllApprovedPresetsUseWallpaperAssets() {
        let assetNames = BackgroundPresetCatalog.all.map { preset in
            BackgroundRenderResolver.wallpaperAssetName(for: preset)
        }

        XCTAssertEqual(assetNames, [
            "BackgroundAuroraAir",
            "BackgroundSunsetBloom",
            "BackgroundMidnightPulse",
            "BackgroundSilverMist",
            "BackgroundSoftGlass",
            "BackgroundTidalGlow",
            "BackgroundLuminousDrift",
            "BackgroundHorizonGlow",
        ])
    }
}
