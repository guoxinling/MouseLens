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

enum CaptionLocaleCatalog {
    static func supportedLocaleIdentifiers(
        systemLocaleIdentifier: String = Locale.current.identifier
    ) -> [String] {
        var identifiers: [String] = []
        append(systemLocaleIdentifier, to: &identifiers)
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
}
