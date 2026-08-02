import Foundation

struct TranscriptionRequest: Equatable {
    let audioURL: URL
    let localeIdentifier: String
    let requiresOnDeviceRecognition: Bool

    init(
        audioURL: URL,
        localeIdentifier: String,
        requiresOnDeviceRecognition: Bool = true
    ) {
        self.audioURL = audioURL
        self.localeIdentifier = localeIdentifier
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
    }
}

struct TranscriptResult: Equatable {
    let localeIdentifier: String
    let segments: [CaptionSegment]

    func captionTrack(style: CaptionStyle = .defaultValue) -> CaptionTrack {
        CaptionTrack(
            isEnabled: true,
            localeIdentifier: localeIdentifier,
            segments: segments,
            style: style
        )
    }
}

enum TranscriptionError: Error, Equatable {
    case audioFileUnavailable
    case recognizerUnavailable(localeIdentifier: String)
    case onDeviceRecognitionUnavailable(localeIdentifier: String)
    case authorizationDenied
    case noSpeechDetected
    case recognitionFailed(String)
}

protocol TranscriptionProvider {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptResult
}

struct PreparedTranscriptionAudio {
    let url: URL
    let sourceStartOffset: TimeInterval
    private let cleanupHandler: () -> Void

    init(
        url: URL,
        sourceStartOffset: TimeInterval = 0,
        cleanup: @escaping () -> Void = {}
    ) {
        self.url = url
        self.sourceStartOffset = sourceStartOffset
        self.cleanupHandler = cleanup
    }

    func cleanup() {
        cleanupHandler()
    }
}

protocol TranscriptionAudioPreparing {
    func prepareAudioURL(from sourceURL: URL) async throws -> PreparedTranscriptionAudio
}

struct TranscriptionAudioTrackCandidate: Equatable {
    let index: Int
    let duration: TimeInterval
    let estimatedDataRate: Float
}

enum TranscriptionAudioTrackSelector {
    static func preferredTrackIndex(from candidates: [TranscriptionAudioTrackCandidate]) -> Int? {
        candidates
            .filter { $0.duration > 0.1 }
            .max { lhs, rhs in
                if abs(lhs.estimatedDataRate - rhs.estimatedDataRate) > 1 {
                    return lhs.estimatedDataRate < rhs.estimatedDataRate
                }
                if abs(lhs.duration - rhs.duration) > 0.001 {
                    return lhs.duration < rhs.duration
                }
                return lhs.index > rhs.index
            }?
            .index
    }
}

enum CaptionSegmentGrouper {
    private static let maxPauseBetweenWords: TimeInterval = 0.72
    private static let maxPhraseDuration: TimeInterval = 4.2
    private static let maxPhraseCharacterCount = 46

    static func groupedSegments(
        from segments: [RecognizedSpeechSegment],
        localeIdentifier: String
    ) -> [RecognizedSpeechSegment] {
        let sortedSegments = segments
            .map { segment in
                RecognizedSpeechSegment(
                    start: segment.start,
                    duration: segment.duration,
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { $0.text.isEmpty == false }
            .sorted { lhs, rhs in
                if abs(lhs.start - rhs.start) > 0.0001 {
                    return lhs.start < rhs.start
                }
                return lhs.text < rhs.text
            }

        guard sortedSegments.isEmpty == false else { return [] }

        let usesWordSpacing = Self.usesWordSpacing(localeIdentifier: localeIdentifier)
        var grouped: [RecognizedSpeechSegment] = []
        var current = CaptionPhraseBuilder(firstSegment: sortedSegments[0], usesWordSpacing: usesWordSpacing)

        for segment in sortedSegments.dropFirst() {
            if current.shouldStartNewPhrase(before: segment) {
                grouped.append(current.segment())
                current = CaptionPhraseBuilder(firstSegment: segment, usesWordSpacing: usesWordSpacing)
            } else {
                current.append(segment)
            }
        }

        grouped.append(current.segment())
        return grouped
    }

    private static func usesWordSpacing(localeIdentifier: String) -> Bool {
        let normalizedIdentifier = localeIdentifier.lowercased()
        return normalizedIdentifier.hasPrefix("zh") == false
            && normalizedIdentifier.hasPrefix("ja") == false
            && normalizedIdentifier.hasPrefix("ko") == false
    }

    private struct CaptionPhraseBuilder {
        let start: TimeInterval
        private(set) var end: TimeInterval
        private(set) var text: String
        let usesWordSpacing: Bool

        init(firstSegment: RecognizedSpeechSegment, usesWordSpacing: Bool) {
            self.start = firstSegment.start
            self.end = firstSegment.end
            self.text = firstSegment.text
            self.usesWordSpacing = usesWordSpacing
        }

        func shouldStartNewPhrase(before segment: RecognizedSpeechSegment) -> Bool {
            let pause = segment.start - end
            let nextDuration = segment.end - start
            let nextCharacterCount = text.count + segment.text.count + (usesWordSpacing ? 1 : 0)
            return pause > maxPauseBetweenWords
                || nextDuration > maxPhraseDuration
                || nextCharacterCount > maxPhraseCharacterCount
                || Self.endsWithSentencePunctuation(text)
        }

        mutating func append(_ segment: RecognizedSpeechSegment) {
            if usesWordSpacing {
                text += " " + segment.text
            } else {
                text += segment.text
            }
            end = max(end, segment.end)
        }

        func segment() -> RecognizedSpeechSegment {
            RecognizedSpeechSegment(
                start: start,
                duration: max(end - start, 0.12),
                text: text
            )
        }

        private static func endsWithSentencePunctuation(_ text: String) -> Bool {
            guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
                return false
            }
            return ".!?。！？".contains(last)
        }
    }
}

enum SpeechAuthorizationState: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

protocol SpeechAuthorizationClient {
    func authorizationStatus() -> SpeechAuthorizationState
    func requestAuthorization() async -> SpeechAuthorizationState
}

struct RecognizedSpeechSegment: Equatable {
    let start: TimeInterval
    let duration: TimeInterval
    let text: String

    var end: TimeInterval {
        start + max(duration, 0.12)
    }
}

protocol SpeechRecognizerClient {
    var localeIdentifier: String { get }
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }

    func recognizeFile(
        at url: URL,
        requiresOnDeviceRecognition: Bool
    ) async throws -> [RecognizedSpeechSegment]
}

enum CaptionLocaleCatalog {
    static func supportedLocaleIdentifiers(
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages,
        systemLocaleIdentifier: String = Locale.current.identifier
    ) -> [String] {
        var identifiers: [String] = []
        for identifier in preferredLanguageIdentifiers {
            append(identifier, to: &identifiers)
            appendLanguageFallbacks(for: identifier, to: &identifiers)
        }
        append(systemLocaleIdentifier, to: &identifiers)
        appendLanguageFallbacks(for: systemLocaleIdentifier, to: &identifiers)
        append("zh-CN", to: &identifiers)
        append("zh-Hans", to: &identifiers)
        append("en-US", to: &identifiers)
        return identifiers
    }

    private static func append(_ identifier: String, to identifiers: inout [String]) {
        guard identifier.isEmpty == false,
              identifiers.contains(identifier) == false else {
            return
        }
        identifiers.append(identifier)
    }

    private static func appendLanguageFallbacks(for identifier: String, to identifiers: inout [String]) {
        let normalizedIdentifier = identifier.lowercased()
        if normalizedIdentifier.hasPrefix("zh") {
            append("zh-CN", to: &identifiers)
            append("zh-Hans", to: &identifiers)
        } else if normalizedIdentifier.hasPrefix("en") {
            append("en-US", to: &identifiers)
        }
    }
}
