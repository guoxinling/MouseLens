import XCTest
@testable import MouseLens

final class BackgroundPresetCatalogTests: XCTestCase {
    func testCatalogContainsApprovedEightPresetsInDisplayOrder() {
        XCTAssertEqual(BackgroundPresetCatalog.all.map(\.id), [
            "aurora-air",
            "sunset-bloom",
            "midnight-pulse",
            "silver-mist",
            "soft-glass",
            "tidal-glow",
            "luminous-drift",
            "horizon-glow",
        ])
    }

    func testLegacyStyleMapsToNewPresetIDs() {
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .aurora), "aurora-air")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .graphite), "midnight-pulse")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .sunrise), "sunset-bloom")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .ocean), "aurora-air")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .plum), "sunset-bloom")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .moss), "tidal-glow")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .paper), "silver-mist")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .midnight), "midnight-pulse")
    }

    func testProjectStyleDecodesLegacyBackgroundEnumIntoPresetID() throws {
        let data = """
        {
          "aspectRatio": "landscape",
          "background": "aurora",
          "cornerRadius": 10.35,
          "shadowRadius": 0,
          "followStrength": 0.72,
          "clickEmphasis": 0.54,
          "padding": 0.04
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(ProjectStyle.self, from: data)

        XCTAssertEqual(style.backgroundPresetID, "aurora-air")
    }
}
