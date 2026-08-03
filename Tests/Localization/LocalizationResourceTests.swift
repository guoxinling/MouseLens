import XCTest

final class LocalizationResourceTests: XCTestCase {
    func testSimplifiedChineseLocalizationIncludesPrimaryUIStrings() throws {
        let stringsURL = try repositoryRoot()
            .appendingPathComponent("Resources/zh-Hans.lproj/Localizable.strings")
        let data = try Data(contentsOf: stringsURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )

        XCTAssertEqual(plist["Record"], "录制")
        XCTAssertEqual(plist["App language"], "应用语言")
        XCTAssertEqual(plist["Record Screen"], "录制屏幕")
        XCTAssertEqual(plist["Record Window"], "录制窗口")
        XCTAssertEqual(plist["Export"], "导出")
        XCTAssertEqual(plist["Estimated max size"], "预计最大体积")
        XCTAssertEqual(plist["Generate Captions"], "生成字幕")
        XCTAssertEqual(plist["Show Presenter"], "显示人像")
        XCTAssertEqual(plist["Bottom Right"], "右下角")
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("MouseLens.xcodeproj").path) {
                return url
            }
        }

        throw NSError(domain: "LocalizationResourceTests", code: 1)
    }
}
