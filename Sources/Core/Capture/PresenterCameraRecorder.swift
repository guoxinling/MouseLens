import AVFoundation
import CoreGraphics
import Foundation

protocol PresenterCameraRecording {
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

private final class LivePresenterCameraWriter: NSObject, PresenterCameraMovieWriting, AVCaptureFileOutputRecordingDelegate {
    let outputURL: URL
    let naturalSize: CGSize

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var stopContinuation: CheckedContinuation<Void, Error>?

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

        guard session.canAddOutput(movieOutput) else {
            throw PresenterCameraRecorderError.unableToStart("MouseLens could not attach the camera movie output.")
        }
        session.addOutput(movieOutput)
    }

    func start() async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        session.startRunning()
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stop() async throws {
        guard movieOutput.isRecording else {
            session.stopRunning()
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            movieOutput.stopRecording()
        }
        session.stopRunning()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        if let error {
            stopContinuation?.resume(throwing: error)
        } else {
            stopContinuation?.resume()
        }
        stopContinuation = nil
    }
}
