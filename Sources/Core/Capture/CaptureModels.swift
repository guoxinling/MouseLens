@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import AppKit
@preconcurrency import CoreImage
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

@_silgen_name("MouseLensAppendSampleBufferCatchingException")
private func MouseLensAppendSampleBufferCatchingException(
    _ input: AVAssetWriterInput,
    _ sampleBuffer: CMSampleBuffer,
    _ errorMessageOut: UnsafeMutablePointer<Unmanaged<CFString>?>
) -> Bool

enum CaptureTarget: String, CaseIterable, Codable {
    case screen
    case window

    var label: String {
        switch self {
        case .screen: "Screen"
        case .window: "Window"
        }
    }
}

struct ScreenRecorderConfiguration: Equatable, Codable {
    let target: CaptureTarget
    let includeMicrophone: Bool
    let includeSystemAudio: Bool
    let preferredWindowID: UInt32?

    init(
        target: CaptureTarget,
        includeMicrophone: Bool,
        includeSystemAudio: Bool,
        preferredWindowID: UInt32? = nil
    ) {
        self.target = target
        self.includeMicrophone = includeMicrophone
        self.includeSystemAudio = includeSystemAudio
        self.preferredWindowID = preferredWindowID
    }
}

struct CaptureViewport: Codable, Equatable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double

    init(rect: CGRect) {
        self.minX = rect.minX
        self.minY = rect.minY
        self.width = rect.width
        self.height = rect.height
    }

    var rect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

struct CaptureCoordinateSpace: Codable, Equatable {
    let viewport: CaptureViewport
    let screenBounds: CaptureViewport
}

struct CaptureWindowOption: Identifiable, Equatable {
    let id: UInt32
    let appName: String
    let title: String
    let frame: CaptureViewport

    var displayLabel: String {
        title.isEmpty ? appName : "\(appName) - \(title)"
    }

    var compactLabel: String {
        title.isEmpty ? appName : title
    }
}

struct CaptureSession: Equatable, Codable {
    let id: UUID
    let configuration: ScreenRecorderConfiguration
    let startedAt: Date
    let endedAt: Date
    let rawCaptureURL: URL?
    let coordinateSpace: CaptureCoordinateSpace?

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

enum ScreenRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case unsupportedSystem
    case noShareableContent
    case selectedWindowUnavailable
    case unableToStart(String)
    case unableToFinalize(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording session is already running."
        case .notRecording:
            "There is no active recording session."
        case .unsupportedSystem:
            "Real recording currently requires macOS 15 or newer."
        case .noShareableContent:
            "MouseLens could not find a screen or window to capture."
        case .selectedWindowUnavailable:
            "The selected window is no longer available. Choose another window and try again."
        case .unableToStart(let reason):
            "MouseLens could not start capture: \(reason)"
        case .unableToFinalize(let reason):
            "MouseLens could not finish capture: \(reason)"
        }
    }
}

private struct CaptureSource {
    let filter: SCContentFilter
    let viewport: CaptureViewport
    let captureSize: CGSize
}

@available(macOS 15.0, *)
private final class StreamFileRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private let logger: Logger
    private let outputURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let microphoneInput: AVAssetWriterInput?
    private let systemAudioInput: AVAssetWriterInput?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let renderColorSpace = CGColorSpaceCreateDeviceRGB()
    let sampleHandlerQueue = DispatchQueue(label: "MouseLens.StreamFileRecorder")
    private var sessionStartPTS: CMTime?
    private var isPaused = false
    private var pendingResume = false
    private var pauseStartedPTS: CMTime?
    private var accumulatedPauseDuration = CMTime.zero
    private var hasLoggedDeferredMicrophone = false
    private var hasLoggedDeferredSystemAudio = false
    private var isFinishing = false
    private var disabledAudioInputs: Set<ObjectIdentifier> = []
    private var lastVideoPresentationTime: CMTime?
    private var lastAudioPresentationTimes: [ObjectIdentifier: CMTime] = [:]

    init(
        outputURL: URL,
        renderSize: CGSize,
        configuration: ScreenRecorderConfiguration,
        logger: Logger
    ) throws {
        self.logger = logger
        self.outputURL = outputURL

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = true

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height)
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw ScreenRecorderError.unableToStart("MouseLens could not attach the video writer input.")
        }
        writer.add(videoInput)

        let audioOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]

        if configuration.includeMicrophone {
            let microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
            microphoneInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(microphoneInput) else {
                throw ScreenRecorderError.unableToStart("MouseLens could not attach the microphone writer input.")
            }
            writer.add(microphoneInput)
            self.microphoneInput = microphoneInput
        } else {
            self.microphoneInput = nil
        }

        if configuration.includeSystemAudio {
            let systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
            systemAudioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(systemAudioInput) else {
                throw ScreenRecorderError.unableToStart("MouseLens could not attach the system audio writer input.")
            }
            writer.add(systemAudioInput)
            self.systemAudioInput = systemAudioInput
        } else {
            self.systemAudioInput = nil
        }

        super.init()
    }

    func setPaused(_ paused: Bool) {
        sampleHandlerQueue.async { [self] in
            if paused {
                guard !isPaused else { return }
                isPaused = true
                pendingResume = false
                pauseStartedPTS = nil
                logger.log("Capture writer paused.")
            } else {
                guard isPaused else { return }
                isPaused = false
                pendingResume = true
                logger.log("Capture writer resumed.")
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .screen:
            appendVideo(sampleBuffer)
        case .microphone:
            guard let microphoneInput else { return }
            append(sampleBuffer, to: microphoneInput, label: "microphone")
        case .audio:
            guard let systemAudioInput else { return }
            append(sampleBuffer, to: systemAudioInput, label: "system audio")
        @unknown default:
            return
        }
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sampleHandlerQueue.async { [self] in
                self.isFinishing = true

                guard self.writer.status != .failed else {
                    continuation.resume(throwing: self.writer.error ?? ScreenRecorderError.unableToFinalize("The capture writer failed."))
                    return
                }

                guard self.writer.status != .unknown else {
                    continuation.resume(throwing: ScreenRecorderError.unableToFinalize("MouseLens did not receive any screen frames."))
                    return
                }

                self.videoInput.markAsFinished()
                self.microphoneInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.writer.finishWriting { [self] in
                    if self.writer.status == .completed {
                        self.logger.log("Capture writer finished at \(self.outputURL.lastPathComponent).")
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: self.writer.error
                                ?? ScreenRecorderError.unableToFinalize("MouseLens could not finalize the capture file.")
                        )
                    }
                }
            }
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rawPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard isUsablePresentationTime(rawPresentationTime) else { return }

        if writer.status == .unknown {
            guard !shouldDropSampleForPause(at: rawPresentationTime) else { return }

            guard writer.startWriting() else {
                isFinishing = true
                logger.log("Capture writer failed to start: \(writer.error?.localizedDescription ?? "Unknown writer error").")
                return
            }
            writer.startSession(atSourceTime: .zero)
            sessionStartPTS = rawPresentationTime
            accumulatedPauseDuration = .zero
            pauseStartedPTS = nil
            pendingResume = false
            logger.log("Capture writer started.")
        }

        guard writer.status == .writing else { return }
        guard videoInput.isReadyForMoreMediaData else { return }
        guard let presentationTime = adjustedPresentationTime(for: rawPresentationTime) else { return }
        guard isStrictlyIncreasing(presentationTime, after: lastVideoPresentationTime) else { return }
        guard let recordingPixelBuffer = makeRecordingPixelBufferCopy(from: pixelBuffer) else {
            logger.log("Capture video append failed: MouseLens could not copy the screen frame into its writer buffer.")
            return
        }

        if videoAdaptor.append(recordingPixelBuffer, withPresentationTime: presentationTime) {
            lastVideoPresentationTime = presentationTime
        } else {
            logger.log("Capture video append failed: \(writer.error?.localizedDescription ?? "Unknown writer error").")
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput, label: String) {
        guard !isFinishing else { return }
        let inputID = ObjectIdentifier(input)
        guard !disabledAudioInputs.contains(inputID) else { return }
        guard isUsableAudioSampleBuffer(sampleBuffer, label: label) else { return }

        guard let sessionStartPTS else {
            if label == "microphone", hasLoggedDeferredMicrophone == false {
                hasLoggedDeferredMicrophone = true
                logger.log("Holding microphone audio until the first video frame arrives.")
            } else if label == "system audio", hasLoggedDeferredSystemAudio == false {
                hasLoggedDeferredSystemAudio = true
                logger.log("Holding system audio until the first video frame arrives.")
            }
            return
        }

        guard writer.status == .writing else { return }
        guard input.isReadyForMoreMediaData else { return }

        let samplePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard isUsablePresentationTime(samplePTS) else { return }
        guard let timingOffset = timingOffset(for: samplePTS) else { return }
        guard samplePTS >= sessionStartPTS else {
            return
        }
        let shiftedPresentationTime = CMTimeSubtract(samplePTS, timingOffset)
        guard isUsablePresentationTime(shiftedPresentationTime) else { return }
        guard CMTimeCompare(shiftedPresentationTime, .zero) >= 0 else { return }
        guard isStrictlyIncreasing(
            shiftedPresentationTime,
            after: lastAudioPresentationTimes[inputID]
        ) else {
            return
        }

        do {
            let shiftedSample = try retimedSampleBuffer(sampleBuffer, subtracting: timingOffset)
            guard CMSampleBufferDataIsReady(shiftedSample) else { return }

            var exceptionMessage: Unmanaged<CFString>?
            let didAppend = MouseLensAppendSampleBufferCatchingException(
                input,
                shiftedSample,
                &exceptionMessage
            )
            if didAppend {
                lastAudioPresentationTimes[inputID] = shiftedPresentationTime
            } else if let exceptionMessage {
                disabledAudioInputs.insert(inputID)
                let message = exceptionMessage.takeRetainedValue() as String
                logger.log("Capture \(label) append threw an exception and that track was disabled: \(message)")
            } else {
                logger.log("Capture \(label) append failed: \(writer.error?.localizedDescription ?? "Unknown writer error").")
            }
        } catch {
            logger.log("Capture \(label) retiming failed: \(error.localizedDescription)")
        }
    }

    private func adjustedPresentationTime(for rawPresentationTime: CMTime) -> CMTime? {
        guard let timingOffset = timingOffset(for: rawPresentationTime) else { return nil }
        let shiftedTime = CMTimeSubtract(rawPresentationTime, timingOffset)
        return CMTimeCompare(shiftedTime, .zero) < 0 ? .zero : shiftedTime
    }

    private func timingOffset(for rawPresentationTime: CMTime) -> CMTime? {
        guard let sessionStartPTS else { return nil }
        guard !shouldDropSampleForPause(at: rawPresentationTime) else { return nil }

        completePendingResumeIfNeeded(at: rawPresentationTime)
        return CMTimeAdd(sessionStartPTS, accumulatedPauseDuration)
    }

    private func shouldDropSampleForPause(at rawPresentationTime: CMTime) -> Bool {
        guard isPaused else { return false }

        if let pauseStartedPTS {
            if CMTimeCompare(rawPresentationTime, pauseStartedPTS) < 0 {
                self.pauseStartedPTS = rawPresentationTime
            }
        } else {
            pauseStartedPTS = rawPresentationTime
        }

        return true
    }

    private func completePendingResumeIfNeeded(at rawPresentationTime: CMTime) {
        guard pendingResume, let pauseStartedPTS else { return }

        let pausedDuration = CMTimeSubtract(rawPresentationTime, pauseStartedPTS)
        guard CMTimeCompare(pausedDuration, .zero) > 0 else { return }

        accumulatedPauseDuration = CMTimeAdd(accumulatedPauseDuration, pausedDuration)
        self.pauseStartedPTS = nil
        pendingResume = false
    }

    private func retimedSampleBuffer(_ sampleBuffer: CMSampleBuffer, subtracting offset: CMTime) throws -> CMSampleBuffer {
        var entryCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &entryCount
        )
        guard entryCount > 0 else {
            throw ScreenRecorderError.unableToFinalize("MouseLens received a captured sample without timing information.")
        }

        var timingInfo = Array(
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: entryCount
        )

        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: entryCount,
            arrayToFill: &timingInfo,
            entriesNeededOut: &entryCount
        )

        for index in timingInfo.indices {
            if timingInfo[index].presentationTimeStamp.isValid {
                timingInfo[index].presentationTimeStamp = CMTimeSubtract(timingInfo[index].presentationTimeStamp, offset)
            }

            if timingInfo[index].decodeTimeStamp.isValid {
                timingInfo[index].decodeTimeStamp = CMTimeSubtract(timingInfo[index].decodeTimeStamp, offset)
            }
        }

        var adjustedSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjustedSampleBuffer
        )

        guard status == noErr, let adjustedSampleBuffer else {
            throw ScreenRecorderError.unableToFinalize("MouseLens could not retime a captured frame.")
        }

        return adjustedSampleBuffer
    }

    private func isUsableAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, label: String) -> Bool {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return false }
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return false }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return false }
        guard CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Audio else {
            logger.log("Dropping \(label) sample because it is not audio.")
            return false
        }
        return true
    }

    private func isUsablePresentationTime(_ time: CMTime) -> Bool {
        time.isValid && time.isNumeric
    }

    private func isStrictlyIncreasing(_ presentationTime: CMTime, after previousTime: CMTime?) -> Bool {
        guard isUsablePresentationTime(presentationTime) else { return false }
        guard let previousTime else { return true }
        return CMTimeCompare(presentationTime, previousTime) > 0
    }

    private func makeRecordingPixelBufferCopy(from sourcePixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool = videoAdaptor.pixelBufferPool else { return nil }

        var copiedPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &copiedPixelBuffer)
        guard status == kCVReturnSuccess, let copiedPixelBuffer else {
            return nil
        }

        let renderBounds = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(copiedPixelBuffer),
            height: CVPixelBufferGetHeight(copiedPixelBuffer)
        )
        let sourceImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        ciContext.render(sourceImage, to: copiedPixelBuffer, bounds: renderBounds, colorSpace: renderColorSpace)
        return copiedPixelBuffer
    }
}

@available(macOS 15.0, *)
private struct ActiveRecording {
    let sessionID: UUID
    let configuration: ScreenRecorderConfiguration
    let startedAt: Date
    let rawCaptureURL: URL
    let coordinateSpace: CaptureCoordinateSpace
    let stream: SCStream
    let fileRecorder: StreamFileRecorder
}

@MainActor
final class ScreenRecorder {
    private let logger: Logger
    private var activeRecordingBox: Any?

    init(logger: Logger) {
        self.logger = logger
    }

    func availableWindowTargets() async throws -> [CaptureWindowOption] {
        guard #available(macOS 15.0, *) else {
            throw ScreenRecorderError.unsupportedSystem
        }

        let shareableContent = try await loadShareableContent()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return selectableWindows(in: shareableContent)
            .sorted { lhs, rhs in
                score(window: lhs, frontmostPID: frontmostPID) > score(window: rhs, frontmostPID: frontmostPID)
            }
            .map { window in
            let appName = window.owningApplication?.applicationName ?? "Unknown App"
            let title = window.title ?? ""
            return CaptureWindowOption(
                id: window.windowID,
                appName: appName,
                title: title,
                frame: CaptureViewport(rect: window.frame)
            )
        }
    }

    func start(configuration: ScreenRecorderConfiguration) async throws -> CaptureSession {
        guard #available(macOS 15.0, *) else {
            throw ScreenRecorderError.unsupportedSystem
        }
        guard activeRecording == nil else {
            throw ScreenRecorderError.alreadyRecording
        }

        let screenBounds = Self.unionRect(for: NSScreen.screens.map(\.frame))
        let shareableContent = try await loadShareableContent()
        let captureSource = try selectCaptureSource(
            for: configuration,
            in: shareableContent,
            screenBounds: screenBounds
        )
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: captureSource.viewport,
            screenBounds: CaptureViewport(rect: screenBounds)
        )

        let startDate = Date()
        let sessionID = UUID()
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseLens-\(sessionID.uuidString)")
            .appendingPathExtension("mov")

        let streamConfiguration = makeStreamConfiguration(
            from: captureSource,
            request: configuration
        )
        let stream = SCStream(
            filter: captureSource.filter,
            configuration: streamConfiguration,
            delegate: nil
        )

        let fileRecorder = try StreamFileRecorder(
            outputURL: scratchURL,
            renderSize: captureSource.captureSize,
            configuration: configuration,
            logger: logger
        )

        do {
            try stream.addStreamOutput(
                fileRecorder,
                type: .screen,
                sampleHandlerQueue: fileRecorder.sampleHandlerQueue
            )
            if configuration.includeMicrophone {
                try stream.addStreamOutput(
                    fileRecorder,
                    type: .microphone,
                    sampleHandlerQueue: fileRecorder.sampleHandlerQueue
                )
            }
            if configuration.includeSystemAudio {
                try stream.addStreamOutput(
                    fileRecorder,
                    type: .audio,
                    sampleHandlerQueue: fileRecorder.sampleHandlerQueue
                )
            }
            try await startCapture(stream: stream)
        } catch {
            throw ScreenRecorderError.unableToStart(error.localizedDescription)
        }

        activeRecording = ActiveRecording(
            sessionID: sessionID,
            configuration: configuration,
            startedAt: startDate,
            rawCaptureURL: scratchURL,
            coordinateSpace: coordinateSpace,
            stream: stream,
            fileRecorder: fileRecorder
        )

        logger.log("Started live capture for \(configuration.target.rawValue) at \(scratchURL.lastPathComponent).")

        return CaptureSession(
            id: sessionID,
            configuration: configuration,
            startedAt: startDate,
            endedAt: startDate,
            rawCaptureURL: scratchURL,
            coordinateSpace: coordinateSpace
        )
    }

    func stop() async throws -> CaptureSession {
        guard #available(macOS 15.0, *) else {
            throw ScreenRecorderError.unsupportedSystem
        }
        guard let activeRecording = activeRecording else {
            throw ScreenRecorderError.notRecording
        }
        defer {
            self.activeRecording = nil
        }

        try await stopCapture(stream: activeRecording.stream)
        try await activeRecording.fileRecorder.finish()

        let session = CaptureSession(
            id: activeRecording.sessionID,
            configuration: activeRecording.configuration,
            startedAt: activeRecording.startedAt,
            endedAt: Date(),
            rawCaptureURL: activeRecording.rawCaptureURL,
            coordinateSpace: activeRecording.coordinateSpace
        )

        logger.log("Stopped live capture after \(String(format: "%.2f", session.duration)) seconds.")
        return session
    }

    func pause() {
        guard #available(macOS 15.0, *), let activeRecording else { return }
        activeRecording.fileRecorder.setPaused(true)
    }

    func resume() {
        guard #available(macOS 15.0, *), let activeRecording else { return }
        activeRecording.fileRecorder.setPaused(false)
    }

    private func makeStreamConfiguration(
        from source: CaptureSource,
        request: ScreenRecorderConfiguration
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scaledSize = source.captureSize

        configuration.width = max(1, Int(scaledSize.width))
        configuration.height = max(1, Int(scaledSize.height))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        // ScreenCaptureKit has been observed to crash during SCStream init on
        // some macOS 15 builds when backgroundColor is populated. Keep the MVP
        // config minimal and only opt into the window-specific flags when they
        // actually apply.
        if request.target == .window {
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
            if #available(macOS 14.2, *) {
                configuration.includeChildWindows = true
            }
        }

        configuration.capturesAudio = request.includeSystemAudio
        configuration.excludesCurrentProcessAudio = false

        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = request.includeMicrophone
        }

        return configuration
    }

    private func loadShareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: ScreenRecorderError.noShareableContent)
                }
            }
        }
    }

    private func selectCaptureSource(
        for configuration: ScreenRecorderConfiguration,
        in shareableContent: SCShareableContent,
        screenBounds: CGRect
    ) throws -> CaptureSource {
        switch configuration.target {
        case .screen:
            return try selectDisplaySource(in: shareableContent)
        case .window:
            return try selectWindowSource(
                for: configuration,
                in: shareableContent,
                screenBounds: screenBounds
            )
        }
    }

    private func selectDisplaySource(in shareableContent: SCShareableContent) throws -> CaptureSource {
        let mainDisplayID = CGMainDisplayID()
        guard let display = shareableContent.displays.first(where: { $0.displayID == mainDisplayID }) ?? shareableContent.displays.first else {
            throw ScreenRecorderError.noShareableContent
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return CaptureSource(
            filter: filter,
            viewport: CaptureViewport(rect: filter.contentRect),
            captureSize: Self.recommendedCaptureSize(for: filter)
        )
    }

    private func selectWindowSource(
        for configuration: ScreenRecorderConfiguration,
        in shareableContent: SCShareableContent,
        screenBounds: CGRect
    ) throws -> CaptureSource {
        let candidates = selectableWindows(in: shareableContent)

        if let preferredWindowID = configuration.preferredWindowID,
           let window = window(matching: preferredWindowID, in: shareableContent) {
            return makeWindowCaptureSource(for: window, screenBounds: screenBounds)
        }

        if configuration.preferredWindowID != nil {
            throw ScreenRecorderError.selectedWindowUnavailable
        }

        guard !candidates.isEmpty else {
            throw ScreenRecorderError.noShareableContent
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let window = candidates.max { lhs, rhs in
            score(window: lhs, frontmostPID: frontmostPID) < score(window: rhs, frontmostPID: frontmostPID)
        }

        guard let window else {
            throw ScreenRecorderError.noShareableContent
        }

        return makeWindowCaptureSource(for: window, screenBounds: screenBounds)
    }

    private func makeWindowCaptureSource(for window: SCWindow, screenBounds: CGRect) -> CaptureSource {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let appKitViewport = Self.appKitViewport(
            fromScreenCaptureKitRect: window.frame,
            screenBounds: screenBounds
        )
        return CaptureSource(
            filter: filter,
            viewport: CaptureViewport(rect: appKitViewport),
            captureSize: Self.recommendedCaptureSize(
                contentRect: window.frame,
                pointPixelScale: CGFloat(filter.pointPixelScale)
            )
        )
    }

    private func window(matching windowID: UInt32, in shareableContent: SCShareableContent) -> SCWindow? {
        shareableContent.windows.first { window in
            window.windowID == windowID && isSelectableWindow(window)
        }
    }

    private func selectableWindows(in shareableContent: SCShareableContent) -> [SCWindow] {
        shareableContent.windows.filter(isSelectableWindow)
    }

    private func isSelectableWindow(_ window: SCWindow) -> Bool {
        guard window.isOnScreen else { return false }
        guard window.frame.width > 120, window.frame.height > 80 else { return false }
        guard window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        guard window.owningApplication?.bundleIdentifier != "com.apple.dock" else { return false }
        guard window.windowLayer >= 0, window.windowLayer <= 20 else { return false }
        return true
    }

    private func score(window: SCWindow, frontmostPID: pid_t?) -> Double {
        let area = window.frame.width * window.frame.height
        let frontmostBoost = (frontmostPID != nil && window.owningApplication?.processID == frontmostPID) ? 10_000_000 : 0
        let activeBoost = window.isActive ? 2_000_000 : 0
        return area + CGFloat(frontmostBoost + activeBoost).doubleValue
    }

    private func startCapture(stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func stopCapture(stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func recommendedCaptureSize(for filter: SCContentFilter) -> CGSize {
        recommendedCaptureSize(contentRect: filter.contentRect, pointPixelScale: CGFloat(filter.pointPixelScale))
    }

    private static func recommendedCaptureSize(contentRect: CGRect, pointPixelScale: CGFloat) -> CGSize {
        let rawSize = CGSize(
            width: max(contentRect.width * pointPixelScale, 1),
            height: max(contentRect.height * pointPixelScale, 1)
        )
        let maxDimension: CGFloat = 2560
        let currentMax = max(rawSize.width, rawSize.height)
        guard currentMax > maxDimension else { return rawSize }
        let scale = maxDimension / currentMax
        return CGSize(width: rawSize.width * scale, height: rawSize.height * scale)
    }

    private static func unionRect(for rects: [CGRect]) -> CGRect {
        rects.reduce(CGRect.null) { partialResult, rect in
            partialResult.union(rect)
        }
    }

    private static func appKitViewport(fromScreenCaptureKitRect rect: CGRect, screenBounds: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenBounds.minY + screenBounds.height - (rect.minY - screenBounds.minY) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    @available(macOS 15.0, *)
    private var activeRecording: ActiveRecording? {
        get { activeRecordingBox as? ActiveRecording }
        set { activeRecordingBox = newValue }
    }
}

private extension CGFloat {
    var doubleValue: Double { Double(self) }
}
