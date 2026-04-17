@preconcurrency import ScreenCaptureKit
import AppKit
import CoreGraphics
import CoreMedia
import Foundation

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
    case unableToStart(String)

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
        case .unableToStart(let reason):
            "MouseLens could not start capture: \(reason)"
        }
    }
}

private struct CaptureSource {
    let filter: SCContentFilter
    let viewport: CaptureViewport
}

@available(macOS 15.0, *)
private final class RecordingOutputObserver: NSObject, SCRecordingOutputDelegate {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        logger.log("ScreenCaptureKit recording output started.")
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        logger.log("ScreenCaptureKit recording output failed: \(error.localizedDescription)")
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        logger.log("ScreenCaptureKit recording output finished.")
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
    let recordingOutputObserver: RecordingOutputObserver
}

@MainActor
final class ScreenRecorder {
    private let logger: Logger
    private var activeRecordingBox: Any?

    init(logger: Logger) {
        self.logger = logger
    }

    func start(configuration: ScreenRecorderConfiguration) async throws -> CaptureSession {
        guard #available(macOS 15.0, *) else {
            throw ScreenRecorderError.unsupportedSystem
        }
        guard activeRecording == nil else {
            throw ScreenRecorderError.alreadyRecording
        }

        let shareableContent = try await loadShareableContent()
        let captureSource = try selectCaptureSource(for: configuration, in: shareableContent)
        let screenBounds = Self.unionRect(for: shareableContent.displays.map(\.frame))
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: captureSource.viewport,
            screenBounds: CaptureViewport(rect: screenBounds)
        )

        let startDate = Date()
        let sessionID = UUID()
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseLens-\(sessionID.uuidString)")
            .appendingPathExtension("mp4")

        let streamConfiguration = makeStreamConfiguration(
            from: captureSource.filter,
            request: configuration
        )
        let stream = SCStream(
            filter: captureSource.filter,
            configuration: streamConfiguration,
            delegate: nil
        )

        let recordingOutputObserver = RecordingOutputObserver(logger: logger)
        let recordingOutputConfiguration = SCRecordingOutputConfiguration()
        recordingOutputConfiguration.outputURL = scratchURL
        recordingOutputConfiguration.videoCodecType = .h264
        recordingOutputConfiguration.outputFileType = .mp4
        let recordingOutput = SCRecordingOutput(
            configuration: recordingOutputConfiguration,
            delegate: recordingOutputObserver
        )

        do {
            try stream.addRecordingOutput(recordingOutput)
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
            recordingOutputObserver: recordingOutputObserver
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

        try await stopCapture(stream: activeRecording.stream)
        try await Task.sleep(nanoseconds: 200_000_000)

        self.activeRecording = nil

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

    private func makeStreamConfiguration(
        from filter: SCContentFilter,
        request: ScreenRecorderConfiguration
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scaledSize = Self.recommendedCaptureSize(for: filter)

        configuration.width = max(1, Int(scaledSize.width))
        configuration.height = max(1, Int(scaledSize.height))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best

        // ScreenCaptureKit has been observed to crash during SCStream init on
        // some macOS 15 builds when backgroundColor is populated. Keep the MVP
        // config minimal and only opt into the window-specific flags when they
        // actually apply.
        if request.target == .window {
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = false
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
        in shareableContent: SCShareableContent
    ) throws -> CaptureSource {
        switch configuration.target {
        case .screen:
            return try selectDisplaySource(in: shareableContent)
        case .window:
            return try selectWindowSource(in: shareableContent)
        }
    }

    private func selectDisplaySource(in shareableContent: SCShareableContent) throws -> CaptureSource {
        let mainDisplayID = CGMainDisplayID()
        guard let display = shareableContent.displays.first(where: { $0.displayID == mainDisplayID }) ?? shareableContent.displays.first else {
            throw ScreenRecorderError.noShareableContent
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return CaptureSource(filter: filter, viewport: CaptureViewport(rect: display.frame))
    }

    private func selectWindowSource(in shareableContent: SCShareableContent) throws -> CaptureSource {
        let selfBundleID = Bundle.main.bundleIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let candidates = shareableContent.windows
            .filter { window in
                window.isOnScreen &&
                window.windowLayer == 0 &&
                window.frame.width > 220 &&
                window.frame.height > 160 &&
                window.owningApplication?.bundleIdentifier != selfBundleID
            }
            .sorted { lhs, rhs in
                score(window: lhs, frontmostPID: frontmostPID) > score(window: rhs, frontmostPID: frontmostPID)
            }

        guard let window = candidates.first else {
            throw ScreenRecorderError.noShareableContent
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return CaptureSource(filter: filter, viewport: CaptureViewport(rect: window.frame))
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
        let rawSize = CGSize(
            width: max(filter.contentRect.width * CGFloat(filter.pointPixelScale), 1),
            height: max(filter.contentRect.height * CGFloat(filter.pointPixelScale), 1)
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

    @available(macOS 15.0, *)
    private var activeRecording: ActiveRecording? {
        get { activeRecordingBox as? ActiveRecording }
        set { activeRecordingBox = newValue }
    }
}

private extension CGFloat {
    var doubleValue: Double { Double(self) }
}
