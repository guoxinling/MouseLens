import Foundation
import Speech

final class AppleSpeechTranscriptionProvider: TranscriptionProvider {
    private let authorizationClient: SpeechAuthorizationClient
    private let recognizerFactory: (Locale) -> SpeechRecognizerClient?
    private let fileExists: (URL) -> Bool

    init(
        authorizationClient: SpeechAuthorizationClient = AppleSpeechAuthorizationClient(),
        recognizerFactory: @escaping (Locale) -> SpeechRecognizerClient? = { locale in
            AppleSpeechRecognizerClient(locale: locale)
        },
        fileExists: @escaping (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    ) {
        self.authorizationClient = authorizationClient
        self.recognizerFactory = recognizerFactory
        self.fileExists = fileExists
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptResult {
        guard fileExists(request.audioURL) else {
            throw TranscriptionError.audioFileUnavailable
        }

        let authorization = await resolvedAuthorization()
        guard authorization == .authorized else {
            throw TranscriptionError.authorizationDenied
        }

        let locale = Locale(identifier: request.localeIdentifier)
        guard let recognizer = recognizerFactory(locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(localeIdentifier: request.localeIdentifier)
        }

        if request.requiresOnDeviceRecognition && recognizer.supportsOnDeviceRecognition == false {
            throw TranscriptionError.onDeviceRecognitionUnavailable(localeIdentifier: request.localeIdentifier)
        }

        do {
            let recognizedSegments = try await recognizer.recognizeFile(
                at: request.audioURL,
                requiresOnDeviceRecognition: request.requiresOnDeviceRecognition
            )
            let captionSegments = recognizedSegments
                .map { segment in
                    CaptionSegment(
                        start: segment.start,
                        end: segment.end,
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

            guard captionSegments.isEmpty == false else {
                throw TranscriptionError.noSpeechDetected
            }

            return TranscriptResult(
                localeIdentifier: recognizer.localeIdentifier,
                segments: captionSegments
            )
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.recognitionFailed(error.localizedDescription)
        }
    }

    private func resolvedAuthorization() async -> SpeechAuthorizationState {
        let status = authorizationClient.authorizationStatus()
        guard status == .notDetermined else {
            return status
        }
        return await authorizationClient.requestAuthorization()
    }
}

struct AppleSpeechAuthorizationClient: SpeechAuthorizationClient {
    func authorizationStatus() -> SpeechAuthorizationState {
        SFSpeechRecognizer.authorizationStatus().captionState
    }

    func requestAuthorization() async -> SpeechAuthorizationState {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status.captionState)
            }
        }
    }
}

final class AppleSpeechRecognizerClient: SpeechRecognizerClient {
    private let recognizer: SFSpeechRecognizer

    var localeIdentifier: String {
        recognizer.locale.identifier
    }

    var isAvailable: Bool {
        recognizer.isAvailable
    }

    var supportsOnDeviceRecognition: Bool {
        recognizer.supportsOnDeviceRecognition
    }

    init?(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return nil
        }
        self.recognizer = recognizer
    }

    func recognizeFile(
        at url: URL,
        requiresOnDeviceRecognition: Bool
    ) async throws -> [RecognizedSpeechSegment] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            _ = recognizer.recognitionTask(with: request) { result, error in
                guard didResume == false else { return }

                if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }

                didResume = true
                let segments = result.bestTranscription.segments.map { segment in
                    RecognizedSpeechSegment(
                        start: segment.timestamp,
                        duration: segment.duration,
                        text: segment.substring
                    )
                }
                continuation.resume(returning: segments)
            }
        }
    }
}

private extension SFSpeechRecognizerAuthorizationStatus {
    var captionState: SpeechAuthorizationState {
        switch self {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorized:
            .authorized
        @unknown default:
            .denied
        }
    }
}
