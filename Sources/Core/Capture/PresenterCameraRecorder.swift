import AVFoundation
import CoreGraphics
import Foundation

protocol PresenterCameraRecording {
    var activePreviewSession: AVCaptureSession? { get }

    func start() async throws -> PresenterRecordingSession
    func updateRenderOffset(_ offset: TimeInterval)
    func stop() async throws -> PresenterMedia?
    func cancel()
}

struct PresenterRecordingSession: Equatable {
    let startedAt: Date
    let previewDeviceName: String
}

protocol PresenterCameraMovieWriting: AnyObject {
    var outputURL: URL { get }
    var naturalSize: CGSize { get }
    var previewSession: AVCaptureSession? { get }

    func start() async throws
    func stop() async throws
}

enum PresenterCameraRecorderError: LocalizedError {
    case alreadyRecording
    case cameraUnavailable
    case unableToStart(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Presenter camera recording is already running."
        case .cameraUnavailable:
            "MouseLens could not find an available camera."
        case .unableToStart(let reason):
            "MouseLens could not start presenter camera recording: \(reason)"
        }
    }
}

final class PresenterCameraRecorder: PresenterCameraRecording {
    struct Device {
        let displayName: String
        let naturalSize: CGSize
        let avDevice: AVCaptureDevice?
    }

    struct DeviceProvider {
        let cameraDevice: () -> Device?

        init(cameraDevice: @escaping () -> Device?) {
            self.cameraDevice = cameraDevice
        }

        static let live = DeviceProvider {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: .unspecified
            )
            guard let avDevice = discovery.devices.first ?? AVCaptureDevice.default(for: .video) else {
                return nil
            }

            let dimensions = CMVideoFormatDescriptionGetDimensions(avDevice.activeFormat.formatDescription)
            return Device(
                displayName: avDevice.localizedName,
                naturalSize: CGSize(width: Int(dimensions.width), height: Int(dimensions.height)),
                avDevice: avDevice
            )
        }
    }

    struct WriterFactory {
        let makeWriter: (URL, Device) throws -> PresenterCameraMovieWriting

        init(makeWriter: @escaping (URL, Device) throws -> PresenterCameraMovieWriting) {
            self.makeWriter = makeWriter
        }

        static let live = WriterFactory { outputURL, device in
            guard let avDevice = device.avDevice else {
                throw PresenterCameraRecorderError.cameraUnavailable
            }
            return try LivePresenterCameraWriter(
                outputURL: outputURL,
                device: avDevice,
                naturalSize: device.naturalSize
            )
        }
    }

    private struct ActiveRecording {
        let startedAt: Date
        let writer: PresenterCameraMovieWriting
        var renderOffset: TimeInterval
    }

    private let writerFactory: WriterFactory
    private let deviceProvider: DeviceProvider
    private let dateProvider: () -> Date
    private let outputURLProvider: () -> URL
    private var activeRecording: ActiveRecording?

    var activePreviewSession: AVCaptureSession? {
        activeRecording?.writer.previewSession
    }

    init(
        writerFactory: WriterFactory = .live,
        deviceProvider: DeviceProvider = .live,
        dateProvider: @escaping () -> Date = Date.init,
        outputURLProvider: @escaping () -> URL = PresenterCameraRecorder.defaultOutputURL
    ) {
        self.writerFactory = writerFactory
        self.deviceProvider = deviceProvider
        self.dateProvider = dateProvider
        self.outputURLProvider = outputURLProvider
    }

    func start() async throws -> PresenterRecordingSession {
        guard activeRecording == nil else {
            throw PresenterCameraRecorderError.alreadyRecording
        }
        guard let device = deviceProvider.cameraDevice() else {
            throw PresenterCameraRecorderError.cameraUnavailable
        }

        let writer = try writerFactory.makeWriter(outputURLProvider(), device)
        try await writer.start()

        let startedAt = dateProvider()
        activeRecording = ActiveRecording(startedAt: startedAt, writer: writer, renderOffset: 0)
        return PresenterRecordingSession(startedAt: startedAt, previewDeviceName: device.displayName)
    }

    func updateRenderOffset(_ offset: TimeInterval) {
        guard var recording = activeRecording else { return }
        recording.renderOffset = offset
        activeRecording = recording
    }

    func stop() async throws -> PresenterMedia? {
        guard let recording = activeRecording else { return nil }
        activeRecording = nil

        try await recording.writer.stop()
        return PresenterMedia(
            sourceVideoURL: recording.writer.outputURL,
            startedAt: recording.startedAt,
            renderOffset: recording.renderOffset,
            naturalSize: recording.writer.naturalSize
        )
    }

    func cancel() {
        guard let recording = activeRecording else { return }
        activeRecording = nil
        Task {
            try? await recording.writer.stop()
        }
    }

    private static func defaultOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseLens-Presenter-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }
}

private final class LivePresenterCameraWriter: NSObject, PresenterCameraMovieWriting, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let outputURL: URL
    let naturalSize: CGSize
    var previewSession: AVCaptureSession? { session }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let recordingQueue = DispatchQueue(label: "MouseLens.PresenterCameraWriter")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var didStartSession = false
    private var didAppendFrame = false
    private var isStopping = false
    private var stopContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuationResumed = false

    init(outputURL: URL, device: AVCaptureDevice, naturalSize: CGSize) throws {
        self.outputURL = outputURL
        self.naturalSize = naturalSize
        super.init()

        session.beginConfiguration()
        session.sessionPreset = .high
        defer {
            session.commitConfiguration()
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw PresenterCameraRecorderError.unableToStart("MouseLens could not attach the camera input.")
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: recordingQueue)
        guard session.canAddOutput(videoOutput) else {
            throw PresenterCameraRecorderError.unableToStart("MouseLens could not attach the camera video output.")
        }
        session.addOutput(videoOutput)
    }

    func start() async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(naturalSize.width),
                AVVideoHeightKey: Int(naturalSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw PresenterCameraRecorderError.unableToStart("MouseLens could not attach the camera asset writer input.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw PresenterCameraRecorderError.unableToStart(writer.error?.localizedDescription ?? "The camera asset writer could not start.")
        }

        recordingQueue.sync {
            self.assetWriter = writer
            self.videoInput = input
            self.didStartSession = false
            self.didAppendFrame = false
            self.isStopping = false
            self.stopContinuation = nil
            self.stopContinuationResumed = false
        }

        session.startRunning()
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation { continuation in
            recordingQueue.async {
                self.stopContinuation = continuation
                self.stopContinuationResumed = false
                self.isStopping = true
                self.finishWriting()
            }
        }
        session.stopRunning()

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? NSNumber
        guard fileSize?.int64Value ?? 0 > 0 else {
            throw PresenterCameraRecorderError.unableToStart("The presenter camera output file was not created.")
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isStopping,
              let assetWriter,
              let videoInput,
              assetWriter.status == .writing else { return }

        if !didStartSession {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: presentationTime)
            didStartSession = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        if videoInput.append(sampleBuffer) {
            didAppendFrame = true
        } else if let error = assetWriter.error {
            finishWriting(error: error)
        }
    }

    private func finishWriting(error: Error? = nil) {
        guard !stopContinuationResumed else { return }
        if let error {
            assetWriter?.cancelWriting()
            resumeStopContinuation(throwing: error)
            return
        }

        guard let assetWriter, let videoInput else {
            resumeStopContinuation()
            return
        }

        guard didAppendFrame else {
            assetWriter.cancelWriting()
            resumeStopContinuation(
                throwing: PresenterCameraRecorderError.unableToStart("The presenter camera did not produce video frames.")
            )
            return
        }

        videoInput.markAsFinished()
        assetWriter.finishWriting { [weak self, weak assetWriter] in
            self?.recordingQueue.async {
                if let error = assetWriter?.error {
                    self?.resumeStopContinuation(throwing: error)
                } else if assetWriter?.status == .completed {
                    self?.resumeStopContinuation()
                } else {
                    self?.resumeStopContinuation(
                        throwing: PresenterCameraRecorderError.unableToStart("The presenter camera writer did not complete.")
                    )
                }
            }
        }
    }

    private func resumeStopContinuation(throwing error: Error? = nil) {
        guard !stopContinuationResumed else { return }
        stopContinuationResumed = true
        let continuation = stopContinuation
        stopContinuation = nil
        assetWriter = nil
        videoInput = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
