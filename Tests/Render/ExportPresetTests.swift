import XCTest
@testable import MouseLens

final class ExportPresetTests: XCTestCase {
    func testDefaultPresetMatchesAspectRatio() {
        XCTAssertEqual(ExportPreset.defaultPreset(for: .landscape), .standardLandscape)
        XCTAssertEqual(ExportPreset.defaultPreset(for: .portrait), .standardPortrait)
        XCTAssertEqual(ExportPreset.defaultPreset(for: .square), .squareSocial)
    }

    func testRenderSizesArePositive() {
        for preset in ExportPreset.allCases {
            XCTAssertGreaterThan(preset.renderSize.width, 0)
            XCTAssertGreaterThan(preset.renderSize.height, 0)
        }
    }
}
