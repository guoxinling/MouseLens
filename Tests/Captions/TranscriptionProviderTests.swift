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

    func testAppleSpeechProviderRejectsMissingAudioFile() async {
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in FakeSpeechRecognizerClient() },
            fileExists: { _ in false }
        )

        await XCTAssertThrowsTranscriptionError(
            try await provider.transcribe(
                TranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/missing.mov"),
                    localeIdentifier: "en-US"
                )
            ),
            .audioFileUnavailable
        )
    }

    func testAppleSpeechProviderMapsDeniedAuthorization() async {
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .denied),
            recognizerFactory: { _ in FakeSpeechRecognizerClient() },
            fileExists: { _ in true }
        )

        await XCTAssertThrowsTranscriptionError(
            try await provider.transcribe(
                TranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/audio.mov"),
                    localeIdentifier: "en-US"
                )
            ),
            .authorizationDenied
        )
    }

    func testAppleSpeechProviderRequiresOnDeviceRecognitionWhenRequested() async {
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in
                FakeSpeechRecognizerClient(
                    supportsOnDeviceRecognition: false
                )
            },
            fileExists: { _ in true }
        )

        await XCTAssertThrowsTranscriptionError(
            try await provider.transcribe(
                TranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/audio.mov"),
                    localeIdentifier: "zh-Hans",
                    requiresOnDeviceRecognition: true
                )
            ),
            .onDeviceRecognitionUnavailable(localeIdentifier: "zh-Hans")
        )
    }

    func testAppleSpeechProviderBuildsTranscriptFromRecognizedSegments() async throws {
        let recognizer = FakeSpeechRecognizerClient(
            recognizedSegments: [
                RecognizedSpeechSegment(start: 1.2, duration: 0.6, text: "world"),
                RecognizedSpeechSegment(start: 0.1, duration: 0.8, text: "hello")
            ]
        )
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in recognizer },
            fileExists: { _ in true }
        )

        let result = try await provider.transcribe(
            TranscriptionRequest(
                audioURL: URL(fileURLWithPath: "/tmp/audio.mov"),
                localeIdentifier: "en-US",
                requiresOnDeviceRecognition: true
            )
        )

        XCTAssertEqual(result.localeIdentifier, "en-US")
        XCTAssertEqual(result.segments.map(\.text), ["hello", "world"])
        XCTAssertEqual(result.segments.map(\.start), [0.1, 1.2])
        XCTAssertEqual(recognizer.lastRequiresOnDeviceRecognition, true)
    }

    func testAppleSpeechProviderMapsEmptyResultsToNoSpeechDetected() async {
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in FakeSpeechRecognizerClient(recognizedSegments: []) },
            fileExists: { _ in true }
        )

        await XCTAssertThrowsTranscriptionError(
            try await provider.transcribe(
                TranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/audio.mov"),
                    localeIdentifier: "en-US"
                )
            ),
            .noSpeechDetected
        )
    }
}

private final class FakeSpeechAuthorizationClient: SpeechAuthorizationClient {
    private let status: SpeechAuthorizationState

    init(status: SpeechAuthorizationState) {
        self.status = status
    }

    func authorizationStatus() -> SpeechAuthorizationState {
        status
    }

    func requestAuthorization() async -> SpeechAuthorizationState {
        status
    }
}

private final class FakeSpeechRecognizerClient: SpeechRecognizerClient {
    let localeIdentifier: String
    let isAvailable: Bool
    let supportsOnDeviceRecognition: Bool
    let recognizedSegments: [RecognizedSpeechSegment]
    private(set) var lastRequiresOnDeviceRecognition: Bool?

    init(
        localeIdentifier: String = "en-US",
        isAvailable: Bool = true,
        supportsOnDeviceRecognition: Bool = true,
        recognizedSegments: [RecognizedSpeechSegment] = [
            RecognizedSpeechSegment(start: 0, duration: 1, text: "hello")
        ]
    ) {
        self.localeIdentifier = localeIdentifier
        self.isAvailable = isAvailable
        self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
        self.recognizedSegments = recognizedSegments
    }

    func recognizeFile(
        at url: URL,
        requiresOnDeviceRecognition: Bool
    ) async throws -> [RecognizedSpeechSegment] {
        lastRequiresOnDeviceRecognition = requiresOnDeviceRecognition
        return recognizedSegments
    }
}

private func XCTAssertThrowsTranscriptionError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expectedError: TranscriptionError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expectedError)", file: file, line: line)
    } catch let error as TranscriptionError {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Unexpected error \(error)", file: file, line: line)
    }
}
