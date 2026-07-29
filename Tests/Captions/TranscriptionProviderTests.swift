import XCTest
@testable import MouseLens

final class TranscriptionProviderTests: XCTestCase {
    func testTranscriptionRequestDefaultsToOnDeviceRecognition() {
        let request = TranscriptionRequest(
            audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            localeIdentifier: "zh-Hans"
        )

        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertEqual(request.localeIdentifier, "zh-Hans")
    }

    func testSupportedCaptionLocalesIncludeChineseEnglishAndSystemLocale() {
        let locales = CaptionLocaleCatalog.supportedLocaleIdentifiers(
            systemLocaleIdentifier: "fr-FR"
        )

        XCTAssertEqual(locales.first, "fr-FR")
        XCTAssertTrue(locales.contains("zh-Hans"))
        XCTAssertTrue(locales.contains("en-US"))
        XCTAssertEqual(Set(locales).count, locales.count)
    }

    func testTranscriptResultBuildsEnabledCaptionTrack() {
        let result = TranscriptResult(
            localeIdentifier: "en-US",
            segments: [
                CaptionSegment(start: 0.2, end: 1.4, text: "First"),
                CaptionSegment(start: 1.4, end: 2.0, text: "Second")
            ]
        )

        let track = result.captionTrack()

        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(track.localeIdentifier, "en-US")
        XCTAssertEqual(track.segments.map(\.text), ["First", "Second"])
    }
}
