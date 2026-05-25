import XCTest
@testable import MouseLens

@MainActor
final class EditorViewModelTests: XCTestCase {
    func testChangingZoomLevelRebuildsDraftProject() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        let originalKeyframes = viewModel.project?.cameraKeyframes ?? []

        viewModel.zoomLevel = 0.85

        let updatedKeyframes = viewModel.project?.cameraKeyframes ?? []
        XCTAssertEqual(viewModel.zoomLevel, 0.85, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.style.clickEmphasis ?? -1, 0.85, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.style.followStrength ?? -1, 0.799, accuracy: 0.0001)
        XCTAssertNotEqual(updatedKeyframes.map(\.zoom), originalKeyframes.map(\.zoom))
    }

    func testEditorDefaultsUseTighterVideoFrame() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.padding, 0.04, accuracy: 0.0001)
        XCTAssertEqual(viewModel.cornerRadius, 10.35, accuracy: 0.0001)
    }

    func testChangingAspectRatioUpdatesDraftAndExportPreset() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.selectedAspectRatio = .portrait

        XCTAssertEqual(viewModel.project?.style.aspectRatio, .portrait)
        XCTAssertEqual(viewModel.exportPreset, .standardPortrait)
    }

    func testPreviewTimestampClampsToProjectDuration() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(4.0)

        XCTAssertEqual(viewModel.previewTimestamp, 1.0, accuracy: 0.0001)
    }

    func testEditorStartsPreviewAtClipBeginning() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)

        XCTAssertEqual(viewModel.previewOffset, 0.0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewTimestamp, 0.0, accuracy: 0.0001)
    }

    func testUpdatingTrimRangeShrinksPreviewWindow() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updateTrimStart(0.25)
        viewModel.updateTrimEnd(0.55)
        viewModel.updatePreviewTimestamp(2.0)

        XCTAssertEqual(viewModel.project?.trimRange.start ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.trimRange.end ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewDuration, 0.30, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewTimestamp, 0.55, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewOffset, 0.30, accuracy: 0.0001)
    }

    func testSplittingClipCreatesSelectableSegments() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(0.5)
        viewModel.splitClipAtPlayhead()

        XCTAssertEqual(viewModel.clipSegments, [
            ProjectTrimRange(start: 0, end: 0.5),
            ProjectTrimRange(start: 0.5, end: 1.0)
        ])
        XCTAssertEqual(viewModel.selectedClipSegmentIndex, 1)
        XCTAssertEqual(viewModel.trimStart, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.trimEnd, 1.0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewDuration, 1.0, accuracy: 0.0001)
    }

    func testDeletingSelectedClipUpdatesPreviewWindow() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(0.5)
        viewModel.splitClipAtPlayhead()
        viewModel.selectClipSegment(at: 0)
        viewModel.deleteSelectedClip()

        XCTAssertEqual(viewModel.clipSegments, [
            ProjectTrimRange(start: 0.5, end: 1.0)
        ])
        XCTAssertEqual(viewModel.selectedClipSegmentIndex, 0)
        XCTAssertEqual(viewModel.trimStart, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.trimEnd, 1.0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewTimestamp, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewDuration, 0.5, accuracy: 0.0001)
    }

    func testResetClipsRestoresFullDurationSegment() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updateTrimStart(0.25)
        viewModel.updateTrimEnd(0.75)
        viewModel.resetClips()

        XCTAssertEqual(viewModel.clipSegments, [
            ProjectTrimRange(start: 0, end: 1.0)
        ])
        XCTAssertEqual(viewModel.selectedClipSegmentIndex, 0)
        XCTAssertEqual(viewModel.trimStart, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.trimEnd, 1.0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.previewDuration, 1.0, accuracy: 0.0001)
    }

    func testAddingManualZoomSegmentUpdatesDraftProject() throws {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(0.35)
        viewModel.addManualZoomSegment()

        let segment = try XCTUnwrap(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(viewModel.manualZoomSegments.count, 1)
        XCTAssertEqual(viewModel.project?.manualZoomSegments.count, 1)
        XCTAssertEqual(segment.zoomLevel, ManualZoomSegment.defaultZoomLevel, accuracy: 0.0001)
        XCTAssertEqual(segment.start, 0.35, accuracy: 0.0001)
        XCTAssertEqual(segment.source, .manual)
        XCTAssertEqual(viewModel.project?.zoomTrackEdited, true)
    }

    func testUpdatingSelectedManualZoomChangesFocusAndLevel() throws {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.addManualZoomSegment()
        viewModel.updateSelectedManualZoomLevel(2.1)
        viewModel.updateSelectedManualZoomFocus(.init(x: 0.72, y: 0.28))

        let segment = try XCTUnwrap(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(segment.zoomLevel, 2.1, accuracy: 0.0001)
        XCTAssertEqual(segment.focus.x, 0.72, accuracy: 0.0001)
        XCTAssertEqual(segment.focus.y, 0.28, accuracy: 0.0001)
        XCTAssertEqual(segment.source, .manual)
        XCTAssertEqual(viewModel.project?.manualZoomSegments.first?.zoomLevel ?? -1, 2.1, accuracy: 0.0001)
    }

    func testConvertingAutoZoomSegmentMakesItManual() throws {
        let viewModel = makeViewModel()
        let autoSegment = ManualZoomSegment(
            start: 0.2,
            end: 0.8,
            focus: .init(x: 0.35, y: 0.45),
            zoomLevel: 1.8,
            source: .auto
        )
        let project = makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            manualZoomSegments: [autoSegment],
            zoomTrackEdited: false
        )

        viewModel.configure(for: project)

        XCTAssertEqual(viewModel.selectedManualZoomSegment?.source, .auto)
        XCTAssertTrue(viewModel.canConvertSelectedZoomSegmentToManual)
        XCTAssertFalse(viewModel.canAdjustSelectedManualZoomArea)

        viewModel.convertSelectedZoomSegmentToManual()

        let segment = try XCTUnwrap(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(segment.source, .manual)
        XCTAssertTrue(viewModel.canAdjustSelectedManualZoomArea)
        XCTAssertEqual(viewModel.project?.zoomTrackEdited, true)
    }

    func testManualZoomAreaAdjustmentIsExplicit() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.addManualZoomSegment()

        XCTAssertFalse(viewModel.isAdjustingManualZoomArea)

        viewModel.toggleManualZoomAreaAdjustment()
        XCTAssertTrue(viewModel.isAdjustingManualZoomArea)

        viewModel.stopManualZoomAreaAdjustment()
        XCTAssertFalse(viewModel.isAdjustingManualZoomArea)
    }

    func testResizingManualZoomSegmentUpdatesTimelineRange() throws {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(0.25)
        viewModel.addManualZoomSegment()

        let id = try XCTUnwrap(viewModel.selectedManualZoomSegmentID)
        viewModel.resizeManualZoomSegmentStart(id: id, startClipOffset: 0.10)
        viewModel.resizeManualZoomSegmentEnd(id: id, endClipOffset: 0.90)

        let segment = try XCTUnwrap(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(segment.start, 0.10, accuracy: 0.0001)
        XCTAssertEqual(segment.end, 0.90, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.manualZoomSegments.first?.start ?? -1, 0.10, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.manualZoomSegments.first?.end ?? -1, 0.90, accuracy: 0.0001)
    }

    func testTimelineHitTestPrefersPlayheadWhenItOverlapsInHandle() {
        let hit = TimelineTrimHitTester.hit(
            pointX: 20,
            selectedStartOffset: 0,
            selectedEndOffset: 1,
            playheadOffset: 0,
            timelineDuration: 1,
            plotWidth: 300,
            insetX: 20,
            handleHitWidth: 52,
            playheadHitWidth: 18
        )

        XCTAssertEqual(hit, .playhead)
    }

    func testTimelineHitTestPrefersPlayheadWhenItOverlapsOutHandle() {
        let hit = TimelineTrimHitTester.hit(
            pointX: 320,
            selectedStartOffset: 0,
            selectedEndOffset: 1,
            playheadOffset: 1,
            timelineDuration: 1,
            plotWidth: 300,
            insetX: 20,
            handleHitWidth: 52,
            playheadHitWidth: 18
        )

        XCTAssertEqual(hit, .playhead)
    }

    func testTimelineHitTestKeepsBoundaryTrimHandleSidesDraggable() {
        let inHit = TimelineTrimHitTester.hit(
            pointX: 30,
            selectedStartOffset: 0,
            selectedEndOffset: 1,
            playheadOffset: 0.5,
            timelineDuration: 1,
            plotWidth: 300,
            insetX: 20,
            handleHitWidth: 52,
            playheadHitWidth: 18
        )
        let outHit = TimelineTrimHitTester.hit(
            pointX: 310,
            selectedStartOffset: 0,
            selectedEndOffset: 1,
            playheadOffset: 0.5,
            timelineDuration: 1,
            plotWidth: 300,
            insetX: 20,
            handleHitWidth: 52,
            playheadHitWidth: 18
        )

        XCTAssertEqual(inHit, .trimStart)
        XCTAssertEqual(outHit, .trimEnd)
    }

    func testDraggingPlayheadDoesNotMutateTrimState() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updateTrimStart(0.2)
        viewModel.updateTrimEnd(0.8)
        viewModel.updatePreviewTimestamp(0.4, refreshPreviewFrame: false)

        XCTAssertEqual(viewModel.previewOffset, 0.4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.trimStart, 0.2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.trimEnd, 0.8, accuracy: 0.0001)
    }

    func testPlaybackProgressUpdateDoesNotMutateTrimState() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updateTrimStart(0.2)
        viewModel.updateTrimEnd(0.8)
        viewModel.updatePreviewTimestamp(0.4, refreshPreviewFrame: false)

        XCTAssertEqual(viewModel.trimStart, 0.2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.trimEnd, 0.8, accuracy: 0.0001)
    }

    func testWindowPointerNormalizationUsesScreenCaptureKitWindowCoordinates() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 450, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.3, y: 0.25),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].location.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 0.5, accuracy: 0.0001)
    }

    func testEventTapGlobalLocationNormalizationUsesAppKitScreenCoordinates() throws {
        let normalized = try XCTUnwrap(EventTapMonitor.normalizedLocation(
            for: CGPoint(x: 300, y: 600),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800)
        ))

        XCTAssertEqual(normalized.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(normalized.y, 0.25, accuracy: 0.0001)
    }

    func testWindowPointerNormalizationKeepsWindowLocalDirections() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 450, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.14, y: 0.1375),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].location.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 0.2, accuracy: 0.0001)
    }

    func testWindowPointerNormalizationUsesFlippedViewportWhenNeeded() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 50, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.3, y: 0.25),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].location.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 0.5, accuracy: 0.0001)
    }

    func testWindowPointerNormalizationDoesNotFallbackToScreenCoordinates() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 450, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.9, y: 0.9),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertTrue(normalized.isEmpty)
    }

    func testScreenPointerNormalizationUsesAppKitCoordinates() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 100, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.3, y: 0.6875),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .screen
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].location.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 0.5, accuracy: 0.0001)
    }

    private func makeViewModel() -> EditorViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProjectStore(rootDirectoryURL: directory)
        let coordinator = ExportCoordinator(renderer: VideoRenderer(), projectStore: store)
        return EditorViewModel(
            exportCoordinator: coordinator,
            previewRenderer: VideoRenderer(),
            cameraPlanEngine: CameraPlanEngine(),
            projectStore: store,
            preferencesStore: AppPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        )
    }

    private func makeProject(
        followStrength: Double,
        aspectRatio: ProjectAspectRatio,
        manualZoomSegments: [ManualZoomSegment] = [],
        zoomTrackEdited: Bool = true
    ) -> RecordingProject {
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.1, y: 0.2), type: .move),
            PointerEvent(timestamp: 0.5, location: .init(x: 0.9, y: 0.7), type: .click)
        ]
        let engine = CameraPlanEngine()
        let keyframes = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: followStrength,
            clickRule: ClickEmphasisRule(boost: 0.42, duration: 0.6)
        )

        return RecordingProject(
            id: UUID(),
            name: "EditorDraft",
            createdAt: Date(),
            duration: 1.0,
            sourceVideoURL: nil,
            events: events,
            cameraKeyframes: keyframes,
            style: ProjectStyle(
                aspectRatio: aspectRatio,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: followStrength,
                clickEmphasis: 0.42,
                padding: 0.08
            ),
            manualZoomSegments: manualZoomSegments,
            zoomTrackEdited: zoomTrackEdited
        )
    }
}
