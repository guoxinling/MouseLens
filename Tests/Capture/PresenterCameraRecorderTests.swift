import AVFoundation
import CoreGraphics
import Foundation
import XCTest
@testable import MouseLens

final class PresenterCameraRecorderTests: XCTestCase {
    func testPresenterRecorderReturnsSessionOnStart() async throws {
        let startedAt = Date(timeIntervalSince1970: 12)
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockSuccess,
            deviceProvider: .mockBuiltInCamera,
            dateProvider: { startedAt }
        )

        let session = try await recorder.start()

        XCTAssertEqual(session, PresenterRecordingSession(startedAt: startedAt, previewDeviceName: "Mock Camera"))
    }

    func testPresenterRecorderExposesPreviewSessionWhileRecording() async throws {
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockSuccess,
            deviceProvider: .mockBuiltInCamera
        )

        XCTAssertNil(recorder.activePreviewSession)

        _ = try await recorder.start()

        XCTAssertNotNil(recorder.activePreviewSession)
    }

    func testPresenterRecorderStopReturnsMediaWithNaturalSize() async throws {
        let startedAt = Date(timeIntervalSince1970: 24)
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockSuccess,
            deviceProvider: .mockBuiltInCamera,
            dateProvider: { startedAt }
        )

        _ = try await recorder.start()
        let media = try await recorder.stop()

        XCTAssertEqual(media?.sourceVideoURL, URL(fileURLWithPath: "/tmp/mock-presenter.mov"))
        XCTAssertEqual(media?.startedAt, startedAt)
        XCTAssertEqual(media?.renderOffset, 0)
        XCTAssertEqual(media?.naturalSize, CGSize(width: 1280, height: 720))
        XCTAssertNil(recorder.activePreviewSession)
    }

    func testPresenterRecorderUsesUpdatedRenderOffset() async throws {
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockSuccess,
            deviceProvider: .mockBuiltInCamera
        )

        _ = try await recorder.start()
        recorder.updateRenderOffset(0.42)
        let media = try await recorder.stop()

        XCTAssertEqual(try XCTUnwrap(media?.renderOffset), 0.42, accuracy: 0.0001)
    }

    func testPresenterRecorderThrowsWhenWriterStopFails() async throws {
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockStopFailure,
            deviceProvider: .mockBuiltInCamera
        )

        _ = try await recorder.start()

        do {
            _ = try await recorder.stop()
            XCTFail("Expected presenter recorder stop to throw.")
        } catch {
            XCTAssertNil(recorder.activePreviewSession)
        }
    }

    func testPresenterRecorderCancelStopsWithoutMedia() async throws {
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockSuccess,
            deviceProvider: .mockBuiltInCamera
        )

        _ = try await recorder.start()
        XCTAssertNotNil(recorder.activePreviewSession)
        recorder.cancel()
        let media = try await recorder.stop()

        XCTAssertNil(media)
        XCTAssertNil(recorder.activePreviewSession)
    }
}

private extension PresenterCameraRecorder.DeviceProvider {
    static let mockBuiltInCamera = PresenterCameraRecorder.DeviceProvider {
        PresenterCameraRecorder.Device(
            displayName: "Mock Camera",
            naturalSize: CGSize(width: 1280, height: 720),
            avDevice: nil
        )
    }
}

private extension PresenterCameraRecorder.WriterFactory {
    static let mockSuccess = PresenterCameraRecorder.WriterFactory { _, device in
        MockPresenterCameraWriter(
            outputURL: URL(fileURLWithPath: "/tmp/mock-presenter.mov"),
            naturalSize: device.naturalSize
        )
    }

    static let mockStopFailure = PresenterCameraRecorder.WriterFactory { _, device in
        MockPresenterCameraWriter(
            outputURL: URL(fileURLWithPath: "/tmp/mock-presenter.mov"),
            naturalSize: device.naturalSize,
            stopError: PresenterCameraRecorderError.unableToStart("Mock stop failure.")
        )
    }
}

private final class MockPresenterCameraWriter: PresenterCameraMovieWriting {
    let outputURL: URL
    let naturalSize: CGSize
    let previewSession: AVCaptureSession? = AVCaptureSession()
    let stopError: Error?
    private(set) var isRecording = false

    init(outputURL: URL, naturalSize: CGSize, stopError: Error? = nil) {
        self.outputURL = outputURL
        self.naturalSize = naturalSize
        self.stopError = stopError
    }

    func start() async throws {
        isRecording = true
    }

    func stop() async throws {
        if let stopError {
            isRecording = false
            throw stopError
        }
        isRecording = false
    }
}
