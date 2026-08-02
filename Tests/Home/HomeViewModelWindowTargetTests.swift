import XCTest
@testable import MouseLens

@MainActor
final class HomeViewModelWindowTargetTests: XCTestCase {
    private let firstWindow = CaptureWindowOption(
        id: 101,
        appName: "Browser",
        title: "Current Space",
        frame: CaptureViewport(rect: .init(x: 0, y: 0, width: 800, height: 600))
    )
    private let previousWindow = CaptureWindowOption(
        id: 202,
        appName: "Editor",
        title: "Previous Selection",
        frame: CaptureViewport(rect: .init(x: 20, y: 20, width: 900, height: 700))
    )

    func testPreferCurrentWindowSelectsFirstSortedTarget() {
        let selectedID = HomeViewModel.resolveWindowTargetID(
            from: [firstWindow, previousWindow],
            previousID: previousWindow.id,
            policy: .preferCurrentWindow
        )

        XCTAssertEqual(selectedID, firstWindow.id)
    }

    func testPreserveSelectionKeepsAvailablePreviousTarget() {
        let selectedID = HomeViewModel.resolveWindowTargetID(
            from: [firstWindow, previousWindow],
            previousID: previousWindow.id,
            policy: .preserveSelection
        )

        XCTAssertEqual(selectedID, previousWindow.id)
    }

    func testPreserveSelectionFallsBackToFirstSortedTarget() {
        let selectedID = HomeViewModel.resolveWindowTargetID(
            from: [firstWindow],
            previousID: previousWindow.id,
            policy: .preserveSelection
        )

        XCTAssertEqual(selectedID, firstWindow.id)
    }

    func testEmptyTargetListClearsSelection() {
        let selectedID = HomeViewModel.resolveWindowTargetID(
            from: [],
            previousID: previousWindow.id,
            policy: .preferCurrentWindow
        )

        XCTAssertNil(selectedID)
    }

    func testAutoRefreshRunsOnlyForIdleWindowCapture() {
        XCTAssertTrue(
            HomeViewModel.shouldAutoRefreshWindowTargets(
                captureTarget: .window,
                recordingState: .idle
            )
        )
        XCTAssertFalse(
            HomeViewModel.shouldAutoRefreshWindowTargets(
                captureTarget: .screen,
                recordingState: .idle
            )
        )
        XCTAssertFalse(
            HomeViewModel.shouldAutoRefreshWindowTargets(
                captureTarget: .window,
                recordingState: .countdown(secondsRemaining: 2)
            )
        )
        XCTAssertFalse(
            HomeViewModel.shouldAutoRefreshWindowTargets(
                captureTarget: .window,
                recordingState: .recording(RecordingSessionState(startedAt: Date()))
            )
        )
    }

    func testWindowRecordingRequiresASelectedTarget() {
        XCTAssertTrue(
            HomeViewModel.isWindowRecordingUnavailable(
                captureTarget: .window,
                selectedWindowTargetID: nil
            )
        )
        XCTAssertFalse(
            HomeViewModel.isWindowRecordingUnavailable(
                captureTarget: .window,
                selectedWindowTargetID: firstWindow.id
            )
        )
        XCTAssertFalse(
            HomeViewModel.isWindowRecordingUnavailable(
                captureTarget: .screen,
                selectedWindowTargetID: nil
            )
        )
    }

    func testRecordingRefreshAlwaysPrefersCurrentWindowEvenWhenSelectionExists() {
        XCTAssertEqual(
            HomeViewModel.windowTargetRefreshPolicyForRecording(selectedWindowTargetID: previousWindow.id),
            .preferCurrentWindow
        )
    }

    func testRecordingRefreshPrefersCurrentWindowWhenSelectionMissing() {
        XCTAssertEqual(
            HomeViewModel.windowTargetRefreshPolicyForRecording(selectedWindowTargetID: nil),
            .preferCurrentWindow
        )
    }

    func testCaptureTargetPreferenceSelfWriteDoesNotReapplyDefaults() {
        XCTAssertFalse(
            HomeViewModel.shouldApplyExternalCaptureTargetPreference(
                current: .window,
                preference: .window
            )
        )
        XCTAssertTrue(
            HomeViewModel.shouldApplyExternalCaptureTargetPreference(
                current: .screen,
                preference: .window
            )
        )
        XCTAssertTrue(
            HomeViewModel.shouldApplyExternalCaptureTargetPreference(
                current: .window,
                preference: .screen
            )
        )
    }

    func testDefaultPresenterBubbleStyleFollowsCapturedMediaAvailability() {
        XCTAssertTrue(HomeViewModel.defaultPresenterBubbleStyle(isEnabled: true).isEnabled)
        XCTAssertFalse(HomeViewModel.defaultPresenterBubbleStyle(isEnabled: false).isEnabled)
    }

    func testPersistedRecordingNotesDropsEmptyText() {
        let notes = RecordingNotes(
            text: "   \n",
            isVisibleDuringRecording: true,
            fontScale: 1.1
        )

        XCTAssertNil(HomeViewModel.persistedRecordingNotes(from: notes))
    }

    func testPersistedRecordingNotesKeepsNonEmptyText() {
        let notes = RecordingNotes(
            text: "Open the dashboard, then explain export.",
            isVisibleDuringRecording: true,
            fontScale: 1.1
        )

        XCTAssertEqual(HomeViewModel.persistedRecordingNotes(from: notes), notes)
    }

    func testRecordingNotesOverlayShowsOnlyDuringCountdownAndRecording() {
        let notes = RecordingNotes(
            text: "Explain the export panel.",
            isVisibleDuringRecording: true,
            fontScale: 1.2
        )

        XCTAssertNil(
            HomeViewModel.recordingNotesOverlayPayload(
                from: notes,
                recordingState: .idle
            )
        )
        XCTAssertEqual(
            HomeViewModel.recordingNotesOverlayPayload(
                from: notes,
                recordingState: .countdown(secondsRemaining: 2)
            ),
            notes
        )
        XCTAssertEqual(
            HomeViewModel.recordingNotesOverlayPayload(
                from: notes,
                recordingState: .recording(RecordingSessionState(startedAt: Date()))
            ),
            notes
        )
    }

    func testRecordingNotesOverlayRequiresVisibleNonEmptyNotes() {
        let hiddenNotes = RecordingNotes(
            text: "Explain the export panel.",
            isVisibleDuringRecording: false,
            fontScale: 1.2
        )
        let emptyNotes = RecordingNotes(
            text: " \n ",
            isVisibleDuringRecording: true,
            fontScale: 1.2
        )

        XCTAssertNil(
            HomeViewModel.recordingNotesOverlayPayload(
                from: hiddenNotes,
                recordingState: .recording(RecordingSessionState(startedAt: Date()))
            )
        )
        XCTAssertNil(
            HomeViewModel.recordingNotesOverlayPayload(
                from: emptyNotes,
                recordingState: .recording(RecordingSessionState(startedAt: Date()))
            )
        )
    }
}
