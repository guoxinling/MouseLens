import Foundation
@preconcurrency import AVFoundation
import Speech

final class AppleSpeechTranscriptionProvider: TranscriptionProvider {
    private let authorizationClient: SpeechAuthorizationClient
    private let recognizerFactory: (Locale) -> SpeechRecognizerClient?
    private let audioPreparer: TranscriptionAudioPreparing
    private let fileExists: (URL) -> Bool

    init(
        authorizationClient: SpeechAuthorizationClient = AppleSpeechAuthorizationClient(),
        recognizerFactory: @escaping (Locale) -> SpeechRecognizerClient? = { locale in
            AppleSpeechRecognizerClient(locale: locale)
        },
        audioPreparer: TranscriptionAudioPreparing = AppleSpeechAudioPreparer(),
        fileExists: @escaping (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    ) {
        self.authorizationClient = authorizationClient
        self.recognizerFactory = recognizerFactory
        self.audioPreparer = audioPreparer
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
            let preparedAudio = try await audioPreparer.prepareAudioURL(from: request.audioURL)
            defer { preparedAudio.cleanup() }
            let recognizedSegments = try await recognizer.recognizeFile(
                at: preparedAudio.url,
                requiresOnDeviceRecognition: request.requiresOnDeviceRecognition
            )
            let captionSegments = CaptionSegmentGrouper.groupedSegments(
                from: recognizedSegments,
                localeIdentifier: request.localeIdentifier
            )
                .map { segment in
                    CaptionSegment(
                        start: segment.start + preparedAudio.sourceStartOffset,
                        end: segment.end + preparedAudio.sourceStartOffset,
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

final class AppleSpeechAudioPreparer: TranscriptionAudioPreparing {
    private static let speechInputVolumeMultiplier: Float = 6.0

    private let fileManager: FileManager
    private let temporaryDirectory: URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func prepareAudioURL(from sourceURL: URL) async throws -> PreparedTranscriptionAudio {
        if Self.isAudioOnlyFile(sourceURL) {
            return PreparedTranscriptionAudio(url: sourceURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = asset.tracks(withMediaType: .audio)
        guard audioTracks.isEmpty == false else {
            throw TranscriptionError.audioFileUnavailable
        }
        let candidates = audioTracks.enumerated().map { index, track in
            TranscriptionAudioTrackCandidate(
                index: index,
                duration: track.timeRange.duration.seconds,
                estimatedDataRate: track.estimatedDataRate
            )
        }
        guard let preferredTrackIndex = TranscriptionAudioTrackSelector.preferredTrackIndex(from: candidates),
              audioTracks.indices.contains(preferredTrackIndex) else {
            throw TranscriptionError.audioFileUnavailable
        }
        let preferredTrack = audioTracks[preferredTrackIndex]

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TranscriptionError.audioFileUnavailable
        }
        let timeRange = preferredTrack.timeRange.duration.isValid && preferredTrack.timeRange.duration.seconds > 0
            ? preferredTrack.timeRange
            : CMTimeRange(start: .zero, duration: asset.duration)
        try compositionTrack.insertTimeRange(timeRange, of: preferredTrack, at: .zero)

        let outputURL = temporaryDirectory
            .appendingPathComponent("mouselens-caption-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? fileManager.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.recognitionFailed("Could not prepare recording audio for captions.")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false
        let mixParameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        mixParameters.setVolume(Self.speechInputVolumeMultiplier, at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [mixParameters]
        exportSession.audioMix = audioMix

        try await exportAudio(using: exportSession)

        let sourceStartOffset = max(preferredTrack.timeRange.start.seconds, 0)
        return PreparedTranscriptionAudio(url: outputURL, sourceStartOffset: sourceStartOffset) { [fileManager] in
            try? fileManager.removeItem(at: outputURL)
        }
    }

    private func exportAudio(using exportSession: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: TranscriptionError.recognitionFailed(
                            exportSession.error?.localizedDescription ?? "Could not prepare recording audio for captions."
                        )
                    )
                default:
                    continuation.resume(
                        throwing: TranscriptionError.recognitionFailed("Could not prepare recording audio for captions.")
                    )
                }
            }
        }
    }

    private static func isAudioOnlyFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "aac", "aif", "aiff", "caf", "m4a", "mp3", "wav":
            true
        default:
            false
        }
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
