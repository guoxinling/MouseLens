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

    func testPresenterRecorderCancelStopsWithoutMedia() async throws {
        let recorder = PresenterCameraRecorder(
            writerFactory: .mockSuccess,
            deviceProvider: .mockBuiltInCamera
        )

        _ = try await recorder.start()
        recorder.cancel()
        let media = try await recorder.stop()

        XCTAssertNil(media)
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
}

private final class MockPresenterCameraWriter: PresenterCameraMovieWriting {
    let outputURL: URL
    let naturalSize: CGSize
    private(set) var isRecording = false

    init(outputURL: URL, naturalSize: CGSize) {
        self.outputURL = outputURL
        self.naturalSize = naturalSize
    }

    func start() async throws {
        isRecording = true
    }

    func stop() async throws {
        isRecording = false
    }
}
