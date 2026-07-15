import XCTest
@testable import MouseLens

final class AppPermissionsTests: XCTestCase {
    func testRecordingReadyRequiresOnlyScreenWhenMicrophoneIsOff() {
        let permissions = AppPermissions(
            screenRecording: .granted,
            microphone: .unknown,
            accessibility: .unknown,
            camera: .denied
        )

        XCTAssertTrue(permissions.recordingReady(requiresMicrophone: false))
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: true))
        XCTAssertTrue(permissions.recordingReady(requiresMicrophone: false, requiresPresenterCamera: false))
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: false, requiresPresenterCamera: true))
    }

    func testNeedsScreenRecordingRelaunchTracksTransientState() {
        let permissions = AppPermissions(
            screenRecording: .requiresRelaunch,
            microphone: .granted,
            accessibility: .unknown,
            camera: .granted
        )

        XCTAssertTrue(permissions.needsScreenRecordingRelaunch)
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: false))
    }
}
