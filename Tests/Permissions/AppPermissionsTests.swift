import XCTest
@testable import MouseLens

final class AppPermissionsTests: XCTestCase {
    func testRecordingReadyRequiresOnlyScreenWhenMicrophoneIsOff() {
        let permissions = AppPermissions(
            screenRecording: .granted,
            microphone: .unknown,
            accessibility: .unknown
        )

        XCTAssertTrue(permissions.recordingReady(requiresMicrophone: false))
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: true))
    }

    func testNeedsScreenRecordingRelaunchTracksTransientState() {
        let permissions = AppPermissions(
            screenRecording: .requiresRelaunch,
            microphone: .granted,
            accessibility: .unknown
        )

        XCTAssertTrue(permissions.needsScreenRecordingRelaunch)
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: false))
    }
}
