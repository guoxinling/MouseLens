import XCTest
@testable import MouseLens

final class AppPermissionsTests: XCTestCase {
    func testRecordingReadyRequiresOnlyScreenWhenMicrophoneIsOff() {
        let permissions = AppPermissions(
            screenRecording: .granted,
            microphone: .unknown
        )

        XCTAssertTrue(permissions.recordingReady(requiresMicrophone: false))
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: true))
    }

    func testNeedsScreenRecordingRelaunchTracksTransientState() {
        let permissions = AppPermissions(
            screenRecording: .requiresRelaunch,
            microphone: .granted
        )

        XCTAssertTrue(permissions.needsScreenRecordingRelaunch)
        XCTAssertFalse(permissions.recordingReady(requiresMicrophone: false))
    }

    func testUnknownPermissionsNoLongerTrackAccessibility() {
        XCTAssertEqual(
            AppPermissions.unknown,
            AppPermissions(
                screenRecording: .unknown,
                microphone: .unknown
            )
        )
    }
}
