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
            preferredLanguageIdentifiers: ["fr-FR"],
            systemLocaleIdentifier: "en-US"
        )

        XCTAssertEqual(locales.first, "fr-FR")
        XCTAssertTrue(locales.contains("zh-Hans"))
        XCTAssertTrue(locales.contains("en-US"))
        XCTAssertEqual(Set(locales).count, locales.count)
    }

    func testSupportedCaptionLocalesPreferMacOSLanguageOrderBeforeCurrentLocale() {
        let locales = CaptionLocaleCatalog.supportedLocaleIdentifiers(
            preferredLanguageIdentifiers: ["zh-Hans-CN", "en-CN"],
            systemLocaleIdentifier: "en-US"
        )

        XCTAssertEqual(locales.prefix(3), ["zh-Hans-CN", "zh-CN", "zh-Hans"])
        XCTAssertLessThan(
            locales.firstIndex(of: "zh-CN") ?? Int.max,
            locales.firstIndex(of: "en-US") ?? Int.max
        )
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
                RecognizedSpeechSegment(start: 2.0, duration: 0.6, text: "world"),
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
                audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
                localeIdentifier: "en-US",
                requiresOnDeviceRecognition: true
            )
        )

        XCTAssertEqual(result.localeIdentifier, "en-US")
        XCTAssertEqual(result.segments.map(\.text), ["hello", "world"])
        XCTAssertEqual(result.segments.map(\.start), [0.1, 2.0])
        XCTAssertEqual(recognizer.lastRequiresOnDeviceRecognition, true)
    }

    func testAppleSpeechProviderGroupsWordSegmentsIntoPhraseCaptions() async throws {
        let recognizer = FakeSpeechRecognizerClient(
            recognizedSegments: [
                RecognizedSpeechSegment(start: 0.10, duration: 0.20, text: "And"),
                RecognizedSpeechSegment(start: 0.32, duration: 0.22, text: "I'll"),
                RecognizedSpeechSegment(start: 0.55, duration: 0.18, text: "show"),
                RecognizedSpeechSegment(start: 0.75, duration: 0.20, text: "you"),
                RecognizedSpeechSegment(start: 2.30, duration: 0.30, text: "Next")
            ]
        )
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in recognizer },
            fileExists: { _ in true }
        )

        let result = try await provider.transcribe(
            TranscriptionRequest(
                audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
                localeIdentifier: "en-US",
                requiresOnDeviceRecognition: true
            )
        )

        XCTAssertEqual(result.segments.map(\.text), ["And I'll show you", "Next"])
        XCTAssertEqual(result.segments.first?.start ?? -1, 0.10, accuracy: 0.0001)
        XCTAssertEqual(result.segments.first?.end ?? -1, 0.95, accuracy: 0.0001)
    }

    func testAppleSpeechProviderGroupsChineseSegmentsWithoutSpaces() async throws {
        let recognizer = FakeSpeechRecognizerClient(
            recognizedSegments: [
                RecognizedSpeechSegment(start: 0.10, duration: 0.20, text: "现在"),
                RecognizedSpeechSegment(start: 0.34, duration: 0.20, text: "开始"),
                RecognizedSpeechSegment(start: 0.58, duration: 0.20, text: "录制")
            ]
        )
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in recognizer },
            fileExists: { _ in true }
        )

        let result = try await provider.transcribe(
            TranscriptionRequest(
                audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
                localeIdentifier: "zh-CN",
                requiresOnDeviceRecognition: true
            )
        )

        XCTAssertEqual(result.segments.map(\.text), ["现在开始录制"])
    }

    func testAppleSpeechProviderOffsetsSegmentsByPreparedAudioSourceStart() async throws {
        let recognizer = FakeSpeechRecognizerClient(
            recognizedSegments: [
                RecognizedSpeechSegment(start: 0.1, duration: 0.8, text: "delayed speech")
            ]
        )
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in recognizer },
            audioPreparer: FakeTranscriptionAudioPreparer(
                preparedURL: URL(fileURLWithPath: "/tmp/prepared-caption-audio.m4a"),
                sourceStartOffset: 0.35
            ),
            fileExists: { _ in true }
        )

        let result = try await provider.transcribe(
            TranscriptionRequest(
                audioURL: URL(fileURLWithPath: "/tmp/source.mov"),
                localeIdentifier: "en-US",
                requiresOnDeviceRecognition: true
            )
        )

        XCTAssertEqual(result.segments.first?.start ?? -1, 0.45, accuracy: 0.0001)
        XCTAssertEqual(result.segments.first?.end ?? -1, 1.25, accuracy: 0.0001)
    }

    func testAppleSpeechProviderRecognizesPreparedAudioInsteadOfRawVideoContainer() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mov")
        let preparedURL = URL(fileURLWithPath: "/tmp/prepared-caption-audio.m4a")
        let recognizer = FakeSpeechRecognizerClient()
        let audioPreparer = FakeTranscriptionAudioPreparer(preparedURL: preparedURL)
        let provider = AppleSpeechTranscriptionProvider(
            authorizationClient: FakeSpeechAuthorizationClient(status: .authorized),
            recognizerFactory: { _ in recognizer },
            audioPreparer: audioPreparer,
            fileExists: { _ in true }
        )

        _ = try await provider.transcribe(
            TranscriptionRequest(
                audioURL: sourceURL,
                localeIdentifier: "zh-Hans",
                requiresOnDeviceRecognition: true
            )
        )

        XCTAssertEqual(audioPreparer.preparedSourceURLs, [sourceURL])
        XCTAssertEqual(recognizer.lastRecognizedURL, preparedURL)
        XCTAssertTrue(audioPreparer.didCleanup)
    }

    func testCaptionAudioTrackSelectionPrefersAudibleTrackOverSilentTrack() {
        let candidates = [
            TranscriptionAudioTrackCandidate(index: 0, duration: 31.2, estimatedDataRate: 2_250),
            TranscriptionAudioTrackCandidate(index: 1, duration: 31.3, estimatedDataRate: 148_477)
        ]

        let selected = TranscriptionAudioTrackSelector.preferredTrackIndex(from: candidates)

        XCTAssertEqual(selected, 1)
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
                    audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
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
    private(set) var lastRecognizedURL: URL?

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
        lastRecognizedURL = url
        lastRequiresOnDeviceRecognition = requiresOnDeviceRecognition
        return recognizedSegments
    }
}

private final class FakeTranscriptionAudioPreparer: TranscriptionAudioPreparing {
    let preparedURL: URL
    let sourceStartOffset: TimeInterval
    private(set) var preparedSourceURLs: [URL] = []
    private(set) var didCleanup = false

    init(
        preparedURL: URL,
        sourceStartOffset: TimeInterval = 0
    ) {
        self.preparedURL = preparedURL
        self.sourceStartOffset = sourceStartOffset
    }

    func prepareAudioURL(from sourceURL: URL) async throws -> PreparedTranscriptionAudio {
        preparedSourceURLs.append(sourceURL)
        return PreparedTranscriptionAudio(url: preparedURL, sourceStartOffset: sourceStartOffset) { [weak self] in
            self?.didCleanup = true
        }
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
