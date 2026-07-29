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

    func testEditorStartsWithRecommendedExportConfiguration() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)

        XCTAssertEqual(viewModel.exportConfiguration, .recommended(for: .landscape))
        XCTAssertFalse(viewModel.isExportConfigurationModified)
        XCTAssertEqual(viewModel.exportButtonLabel, "Export MP4")
    }

    func testEditingAndResettingExportConfiguration() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.updateExportResolution(.p720)
        viewModel.updateExportFrameRate(.fps15)
        viewModel.updateExportQuality(.small)
        viewModel.updateExportIncludesCursor(false)
        viewModel.updateExportIncludesClickFeedback(false)

        XCTAssertTrue(viewModel.isExportConfigurationModified)
        XCTAssertEqual(viewModel.exportConfiguration.resolution, .p720)
        XCTAssertEqual(viewModel.exportConfiguration.frameRate, .fps15)
        XCTAssertEqual(viewModel.exportConfiguration.quality, .small)
        XCTAssertFalse(viewModel.exportConfiguration.includesCursor)
        XCTAssertFalse(viewModel.exportConfiguration.includesClickFeedback)

        viewModel.resetExportConfiguration()

        XCTAssertFalse(viewModel.isExportConfigurationModified)
        XCTAssertEqual(viewModel.exportConfiguration, .recommended(for: .landscape))
    }

    func testExportEstimateUsesConfiguredBitrateAndTrimmedDuration() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        let highEstimate = viewModel.estimatedExportByteCount
        viewModel.updateExportResolution(.p480)
        viewModel.updateExportFrameRate(.fps15)
        viewModel.updateExportQuality(.small)

        XCTAssertGreaterThan(highEstimate, viewModel.estimatedExportByteCount)
        XCTAssertGreaterThan(viewModel.estimatedExportByteCount, 0)
    }

    func testExportEstimateCaptionUsesPlainEstimatedSizeLabel() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.estimatedExportSizeCaption, "Estimated size")
    }

    func testSwitchingToGIFUsesApprovedDefaults() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

        viewModel.updateExportFormat(.gif)

        XCTAssertEqual(viewModel.exportConfiguration.format, .gif)
        XCTAssertEqual(viewModel.exportConfiguration.resolution, .p1080)
        XCTAssertEqual(viewModel.exportConfiguration.frameRate, .fps15)
        XCTAssertEqual(viewModel.exportConfiguration.quality, .balanced)
        XCTAssertEqual(viewModel.exportButtonLabel, "Export GIF")
    }

    func testGIFResolutionCanSwitchTo720p() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))
        viewModel.updateExportFormat(.gif)

        viewModel.updateExportResolution(.p720)

        XCTAssertEqual(viewModel.exportConfiguration.resolution, .p720)
    }

    func testGIFExportShowsApproximateSizeCaption() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

        viewModel.updateExportFormat(.gif)

        XCTAssertEqual(viewModel.estimatedExportSizeCaption, "Approx. size")
    }

    func testSelectingActiveFormatDoesNotResetModifiedConfiguration() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))
        viewModel.updateExportResolution(.p720)

        viewModel.updateExportFormat(.mp4)

        XCTAssertEqual(viewModel.exportConfiguration.format, .mp4)
        XCTAssertEqual(viewModel.exportConfiguration.resolution, .p720)
        XCTAssertTrue(viewModel.isExportConfigurationModified)
    }

    func testLongDurationGIFShowsWarning() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            duration: 12.1
        ))

        viewModel.updateExportFormat(.gif)

        XCTAssertTrue(viewModel.showsGIFDurationWarning)
        XCTAssertEqual(
            viewModel.gifDurationWarningText,
            "Long GIFs can become large. Trim the clip if you want a smaller file."
        )
    }

    func testSwitchingModifiedMP4ConfigurationToGIFNormalizesHiddenValues() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))
        viewModel.updateExportQuality(.small)
        viewModel.updateExportIncludesCursor(false)
        viewModel.updateExportIncludesClickFeedback(false)

        viewModel.updateExportFormat(.gif)

        XCTAssertEqual(viewModel.exportConfiguration.format, .gif)
        XCTAssertEqual(viewModel.exportConfiguration.quality, .balanced)
        XCTAssertTrue(viewModel.exportConfiguration.includesCursor)
        XCTAssertTrue(viewModel.exportConfiguration.includesClickFeedback)
    }

    func testHiddenGIFOnlyValuesStayNormalizedWhenMutated() {
        let viewModel = makeViewModel()
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))
        viewModel.updateExportFormat(.gif)

        viewModel.updateExportQuality(.small)
        viewModel.updateExportIncludesCursor(false)
        viewModel.updateExportIncludesClickFeedback(false)

        XCTAssertEqual(viewModel.exportConfiguration.quality, .balanced)
        XCTAssertTrue(viewModel.exportConfiguration.includesCursor)
        XCTAssertTrue(viewModel.exportConfiguration.includesClickFeedback)
    }

    func testMP4SavePanelConfigurationUsesVideoMetadata() {
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)
        let configuration = ExportConfiguration.recommended(for: .landscape)

        let panelConfiguration = EditorViewModel.exportSavePanelConfiguration(
            for: project,
            configuration: configuration
        )

        XCTAssertEqual(panelConfiguration.title, "Export MP4")
        XCTAssertEqual(panelConfiguration.message, "Choose where MouseLens should save the exported video.")
        XCTAssertEqual(panelConfiguration.allowedContentTypes, [.mpeg4Movie])
        XCTAssertEqual(panelConfiguration.requiredPathExtension, "mp4")
        XCTAssertEqual(
            panelConfiguration.defaultFilename,
            ExportCoordinator.exportFilename(for: project, configuration: configuration)
        )
    }

    func testGIFSavePanelConfigurationUsesGIFMetadata() {
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)
        let configuration = ExportConfiguration.recommended(for: .landscape, format: .gif)

        let panelConfiguration = EditorViewModel.exportSavePanelConfiguration(
            for: project,
            configuration: configuration
        )

        XCTAssertEqual(panelConfiguration.title, "Export GIF")
        XCTAssertEqual(panelConfiguration.message, "Choose where MouseLens should save the exported GIF.")
        XCTAssertEqual(panelConfiguration.allowedContentTypes, [.gif])
        XCTAssertEqual(panelConfiguration.requiredPathExtension, "gif")
        XCTAssertEqual(
            panelConfiguration.defaultFilename,
            ExportCoordinator.exportFilename(for: project, configuration: configuration)
        )
    }

    func testSavePanelNormalizationReplacesMismatchedExtension() {
        let selectedURL = URL(fileURLWithPath: "/tmp/MouseLens Export.mp4")

        let normalizedURL = EditorViewModel.normalizedExportDestinationURL(
            selectedURL,
            requiredPathExtension: "gif"
        )

        XCTAssertEqual(normalizedURL.lastPathComponent, "MouseLens Export.gif")
    }

    func testSavePanelNormalizationAppendsMissingExtension() {
        let selectedURL = URL(fileURLWithPath: "/tmp/MouseLens Export")

        let normalizedURL = EditorViewModel.normalizedExportDestinationURL(
            selectedURL,
            requiredPathExtension: "mp4"
        )

        XCTAssertEqual(normalizedURL.lastPathComponent, "MouseLens Export.mp4")
    }

    func testGIFExportUsesRendererPathWhenSelected() async {
        var capturedPanelConfiguration: EditorViewModel.ExportSavePanelConfiguration?
        let selectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let expectedURL = selectedURL.deletingPathExtension().appendingPathExtension("gif")
        let viewModel = makeViewModel { _, configuration in
            capturedPanelConfiguration = configuration
            return selectedURL
        }
        viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

        viewModel.updateExportFormat(.gif)

        XCTAssertTrue(viewModel.canExportSelectedFormat)

        await viewModel.export()

        guard case .finished(let exportedURL) = viewModel.exportState else {
            return XCTFail("Expected GIF export to finish through the renderer path.")
        }

        XCTAssertEqual(capturedPanelConfiguration?.allowedContentTypes, [.gif])
        XCTAssertEqual(capturedPanelConfiguration?.requiredPathExtension, "gif")
        XCTAssertEqual(exportedURL, expectedURL)
        XCTAssertEqual(viewModel.exportURL, expectedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertTrue(viewModel.showExportSheet)
    }

    func testHigherResolutionAndFrameRateIncreaseEstimate() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        let recommendedEstimate = viewModel.estimatedExportByteCount

        viewModel.updateExportResolution(.p2160)
        viewModel.updateExportFrameRate(.fps60)

        XCTAssertGreaterThan(viewModel.estimatedExportByteCount, recommendedEstimate)
    }

    func testChangingAspectRatioUpdatesDraftAndExportPreset() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.selectedAspectRatio = .portrait

        XCTAssertEqual(viewModel.project?.style.aspectRatio, .portrait)
        XCTAssertEqual(viewModel.exportPreset, .standardPortrait)
    }

    func testEditorUsesBackgroundPresetIDFromProject() {
        let viewModel = makeViewModel()
        let project = makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            backgroundPresetID: "soft-glass"
        )

        viewModel.configure(for: project)

        XCTAssertEqual(viewModel.selectedBackgroundPresetID, "soft-glass")
        XCTAssertEqual(viewModel.project?.style.backgroundPresetID, "soft-glass")
    }

    func testChangingBackgroundPresetUpdatesDraftProjectStyle() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        viewModel.selectedBackgroundPresetID = "horizon-glow"

        XCTAssertEqual(viewModel.project?.style.backgroundPresetID, "horizon-glow")
        XCTAssertEqual(viewModel.selectedBackgroundPresetID, "horizon-glow")
    }

    func testConfiguringEditorLoadsPresenterBubbleState() {
        let project = makeProjectWithPresenterBubble()
        let viewModel = makeViewModel()

        viewModel.configure(for: project)

        XCTAssertTrue(viewModel.canEditPresenterBubble)
        XCTAssertTrue(viewModel.isPresenterBubbleEnabled)
        XCTAssertEqual(viewModel.presenterBubblePosition, .bottomRight)
        XCTAssertEqual(viewModel.presenterBubbleSize, 0.26, accuracy: 0.0001)
        XCTAssertEqual(viewModel.presenterBubbleCornerRadiusRatio, 0.22, accuracy: 0.0001)
    }

    func testConfiguringEditorWithoutPresenterMediaHidesPresenterControls() {
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)
        let viewModel = makeViewModel()

        viewModel.configure(for: project)

        XCTAssertFalse(viewModel.canEditPresenterBubble)
    }

    func testUpdatingPresenterBubbleRebuildsDraftProject() {
        let project = makeProjectWithPresenterBubble()
        let viewModel = makeViewModel()
        viewModel.configure(for: project)

        viewModel.updatePresenterBubblePosition(.topLeft)
        viewModel.updatePresenterBubbleSize(0.31)
        viewModel.updatePresenterBubbleCornerRadiusRatio(0.5)
        viewModel.updatePresenterBubbleEnabled(false)

        let style = viewModel.project?.style.presenterBubbleStyle
        XCTAssertEqual(style?.position, .topLeft)
        XCTAssertEqual(style?.normalizedSize ?? -1, 0.31, accuracy: 0.0001)
        XCTAssertEqual(style?.cornerRadiusRatio ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style?.isEnabled, false)
        XCTAssertEqual(viewModel.project?.presenterMedia, project.presenterMedia)
    }

    func testPresenterBubbleCornerPresetsUseVisibleCanvasEdges() {
        let project = makeProjectWithPresenterBubble()
        let viewModel = makeViewModel()
        viewModel.configure(for: project)

        viewModel.updatePresenterBubblePosition(.topLeft)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.y ?? -1, 0, accuracy: 0.0001)

        viewModel.updatePresenterBubblePosition(.topRight)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.x ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.y ?? -1, 0, accuracy: 0.0001)

        viewModel.updatePresenterBubblePosition(.bottomLeft)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.y ?? -1, 1, accuracy: 0.0001)

        viewModel.updatePresenterBubblePosition(.bottomRight)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.x ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.normalizedCenter.y ?? -1, 1, accuracy: 0.0001)
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
        viewModel.selectManualZoomSegment(id: autoSegment.id)

        XCTAssertEqual(viewModel.selectedManualZoomSegment?.source, .auto)
        XCTAssertTrue(viewModel.canConvertSelectedZoomSegmentToManual)
        XCTAssertFalse(viewModel.canAdjustSelectedManualZoomArea)

        viewModel.convertSelectedZoomSegmentToManual()

        let segment = try XCTUnwrap(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(segment.source, .manual)
        XCTAssertTrue(viewModel.canAdjustSelectedManualZoomArea)
        XCTAssertEqual(viewModel.project?.zoomTrackEdited, true)
    }

    func testSplittingSelectedManualZoomSegmentAtPlayheadPreservesSource() throws {
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
        viewModel.updatePreviewTimestamp(0.5)
        viewModel.selectManualZoomSegment(id: autoSegment.id)
        XCTAssertTrue(viewModel.canSplitTimelineSelection)

        viewModel.splitTimelineSelectionAtPlayhead()

        XCTAssertEqual(viewModel.manualZoomSegments.count, 2)
        XCTAssertEqual(viewModel.manualZoomSegments[0].start, 0.2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.manualZoomSegments[0].end, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.manualZoomSegments[1].start, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.manualZoomSegments[1].end, 0.8, accuracy: 0.0001)
        XCTAssertTrue(viewModel.manualZoomSegments.allSatisfy { $0.source == .auto })
        XCTAssertEqual(viewModel.project?.zoomTrackEdited, true)
    }

    func testDeletingTimelineSelectionDeletesZoomBeforeClip() throws {
        let viewModel = makeViewModel()
        let segment = ManualZoomSegment(
            start: 0.2,
            end: 0.8,
            focus: .center,
            zoomLevel: 1.7,
            source: .manual
        )
        let project = makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            manualZoomSegments: [segment],
            zoomTrackEdited: true
        )

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(0.5)
        viewModel.splitClipAtPlayhead()
        XCTAssertEqual(viewModel.clipSegments.count, 2)
        viewModel.selectManualZoomSegment(id: segment.id)

        viewModel.deleteTimelineSelection()

        XCTAssertTrue(viewModel.manualZoomSegments.isEmpty)
        XCTAssertEqual(viewModel.clipSegments.count, 2)
        XCTAssertEqual(viewModel.project?.zoomTrackEdited, true)
    }

    func testSelectingClipClearsZoomSelectionSoClipActionsStayAvailable() throws {
        let viewModel = makeViewModel()
        let segment = ManualZoomSegment(
            start: 0.2,
            end: 0.8,
            focus: .center,
            zoomLevel: 1.7,
            source: .manual
        )
        let project = makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            manualZoomSegments: [segment],
            zoomTrackEdited: true
        )

        viewModel.configure(for: project)
        viewModel.updatePreviewTimestamp(0.5)
        viewModel.splitClipAtPlayhead()
        viewModel.selectManualZoomSegment(id: segment.id)
        XCTAssertNotNil(viewModel.selectedManualZoomSegment)

        viewModel.selectClipSegment(at: 0)

        XCTAssertNil(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(viewModel.timelineSelectionLabel, "Clip")
        XCTAssertTrue(viewModel.canDeleteTimelineSelection)
        XCTAssertFalse(viewModel.canSplitTimelineSelection)
    }

    func testExistingZoomTrackDoesNotAutoSelectZoomSegmentOnOpen() {
        let viewModel = makeViewModel()
        let segment = ManualZoomSegment(
            start: 0.2,
            end: 0.8,
            focus: .center,
            zoomLevel: 1.7,
            source: .manual
        )
        let project = makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            manualZoomSegments: [segment],
            zoomTrackEdited: true
        )

        viewModel.configure(for: project)

        XCTAssertNil(viewModel.selectedManualZoomSegment)
        XCTAssertEqual(viewModel.timelineSelectionLabel, "Clip")
        XCTAssertFalse(viewModel.canDeleteTimelineSelection)
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

    func testPreviewPlaybackTimelineUsesClipOffsetsForTrimmedPlayback() {
        let baseProject = makeProject(
            followStrength: 0.65,
            aspectRatio: .landscape,
            duration: 15.0
        )
        let project = baseProject.updating(
            style: baseProject.style,
            cameraKeyframes: baseProject.cameraKeyframes,
            trimRange: ProjectTrimRange(start: 10.0, end: 15.0),
            clipSegments: [ProjectTrimRange(start: 10.0, end: 15.0)]
        )
        let timeline = PreviewPlaybackTimeline(
            project: project,
            displayDuration: project.trimmedDuration,
            usesSourceTimeline: true
        )

        XCTAssertEqual(timeline.displayTime(forPlaybackTime: 10.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.displayTime(forPlaybackTime: 12.5), 2.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.displayTime(forPlaybackTime: 15.0), 5.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.sourceTime(forDisplayTime: 0.0), 10.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.sourceTime(forDisplayTime: 2.5), 12.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.sourceTime(forDisplayTime: 5.0), 15.0, accuracy: 0.0001)
    }

    func testPlaybackControlsFooterSitsOutsidePreviewStage() {
        let stageFrame = CGRect(x: 40, y: 20, width: 1280, height: 720)

        let footerFrame = PreviewPlaybackControlsPlacement.footerFrame(below: stageFrame)

        XCTAssertEqual(footerFrame.minY, stageFrame.maxY, accuracy: 0.0001)
        XCTAssertEqual(footerFrame.width, stageFrame.width, accuracy: 0.0001)
        XCTAssertFalse(footerFrame.intersects(stageFrame))
    }

    func testPlayablePreviewHidesRedundantMetadataRow() {
        XCTAssertFalse(
            PreviewFooterMetadataPolicy.showsMetadataRow(
                hasPlayablePreview: true,
                previewState: .ready
            )
        )
    }

    func testPreviewRefreshIsOnlyPromotedWhenPreviewFailed() {
        XCTAssertFalse(PreviewFooterMetadataPolicy.promotesRefreshAction(previewState: .ready))
        XCTAssertTrue(PreviewFooterMetadataPolicy.promotesRefreshAction(previewState: .failed("Preview failed")))
    }

    func testLivePreviewUsesSingleBackgroundLayer() {
        XCTAssertFalse(PreviewStageBackgroundPolicy.drawsOuterBackground(usesLiveStylePlayback: true))
        XCTAssertTrue(PreviewStageBackgroundPolicy.drawsOuterBackground(usesLiveStylePlayback: false))
    }

    func testPreviewCardClipsWallpaperToRoundedPanel() {
        XCTAssertTrue(PreviewCardStylePolicy.clipsContent)
    }

    func testLivePreviewBackgroundIsConstrainedToStageBounds() {
        XCTAssertTrue(PreviewStageBackgroundPolicy.constrainsBackgroundToStageBounds)
    }

    func testPreviewStageIsCenteredInsidePreviewCard() {
        XCTAssertTrue(PreviewStageBackgroundPolicy.centersStageInPreviewCard)
    }

    func testPresenterPlaybackUsesMirroredVideoLayerTransform() {
        let transform = PresenterPlaybackMirrorPolicy.videoLayerTransform

        XCTAssertEqual(transform.m11, -1, accuracy: 0.0001)
        XCTAssertEqual(transform.m22, 1, accuracy: 0.0001)
    }

    func testSpaceKeyTogglesPlayablePreview() {
        XCTAssertTrue(
            PreviewKeyboardShortcutPolicy.shouldTogglePlayback(
                keyCode: 49,
                charactersIgnoringModifiers: " ",
                modifierFlags: []
            )
        )
    }

    func testModifiedSpaceKeyDoesNotTogglePlayablePreview() {
        XCTAssertFalse(
            PreviewKeyboardShortcutPolicy.shouldTogglePlayback(
                keyCode: 49,
                charactersIgnoringModifiers: " ",
                modifierFlags: [.command]
            )
        )
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

    func testEventTapUsesFallbackMouseLocationForGlobalEventsWithoutWindow() throws {
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 300, y: 600),
            modifierFlags: [],
            timestamp: 12.0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        let location = EventTapMonitor.globalLocation(
            for: click,
            fallbackMouseLocation: CGPoint(x: 300, y: 560)
        )

        XCTAssertEqual(location.x, 300, accuracy: 0.0001)
        XCTAssertEqual(location.y, 560, accuracy: 0.0001)
    }

    func testPointerEventStorePreservesRawGlobalLocation() throws {
        let store = PointerEventStore()
        store.reset(origin: Date())
        store.append(
            location: NormalizedPoint(x: 0.3, y: 0.25),
            globalLocation: CGPoint(x: 300, y: 600),
            type: .click
        )

        let event = try XCTUnwrap(store.snapshot().first)
        let globalLocation = try XCTUnwrap(event.globalLocation)
        XCTAssertEqual(globalLocation.x, 300, accuracy: 0.0001)
        XCTAssertEqual(globalLocation.y, 600, accuracy: 0.0001)
    }

    func testPointerNormalizationPrefersRawGlobalLocationOverLegacyNormalizedLocation() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 450, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.9, y: 0.9),
            globalLocation: PointerGlobalLocation(x: 300, y: 600),
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
        let globalLocation = try? XCTUnwrap(normalized[0].globalLocation)
        XCTAssertEqual(globalLocation?.x ?? 0, 300, accuracy: 0.0001)
        XCTAssertEqual(globalLocation?.y ?? 0, 600, accuracy: 0.0001)
    }

    func testWindowPointerNormalizationAcceptsRecordedWindowViewportCoordinates() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 206, y: 294, width: 1024, height: 680)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: -180, width: 3360, height: 1080))
        )
        let event = PointerEvent(
            timestamp: 0.88,
            location: NormalizedPoint(x: 0.1085600353422619, y: 0.16571180555555554),
            globalLocation: PointerGlobalLocation(x: 364.76171875, y: 721.03125),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].location.x, 0.1550407410, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 0.372013, accuracy: 0.0001)
    }

    func testFullscreenBrowserWindowPointerNormalizationUsesRawViewportNotVisibleCrop() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1470, height: 835)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1470, height: 956))
        )
        let topLeftClick = PointerEvent(
            timestamp: 1.41,
            location: NormalizedPoint(x: 0.13, y: 0.18),
            globalLocation: PointerGlobalLocation(x: 237.3359375, y: 801.52734375),
            type: .click
        )
        let rightTopClick = PointerEvent(
            timestamp: 12.54,
            location: NormalizedPoint(x: 0.99, y: 0.18),
            globalLocation: PointerGlobalLocation(x: 1379.546875, y: 801.1171875),
            type: .click
        )
        let farRightClick = PointerEvent(
            timestamp: 24.07,
            location: NormalizedPoint(x: 0.98, y: 0.15),
            globalLocation: PointerGlobalLocation(x: 1439.95703125, y: 817.34765625),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [topLeftClick, rightTopClick, farRightClick],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0].location.x, 0.161453, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 0.040086, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].location.x, 0.938467, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].location.y, 0.040577, accuracy: 0.0001)
        XCTAssertEqual(normalized[2].location.x, 0.979562, accuracy: 0.0001)
        XCTAssertEqual(normalized[2].location.y, 0.021141, accuracy: 0.0001)
    }

    func testPointerEventStoreCanUseCaptureStartOrigin() {
        let store = PointerEventStore()
        store.reset(origin: Date().addingTimeInterval(-2))
        store.append(location: .center, type: .click)

        let event = store.snapshot().first
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.timestamp ?? 0, 2, accuracy: 0.2)
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

    func testWindowPointerNormalizationDoesNotGuessFlippedViewport() {
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

        XCTAssertTrue(normalized.isEmpty)
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

    func testWindowPointerNormalizationKeepsNearEdgeClicksWithSmallTolerance() {
        let coordinateSpace = CaptureCoordinateSpace(
            viewport: CaptureViewport(rect: CGRect(x: 100, y: 450, width: 400, height: 300)),
            screenBounds: CaptureViewport(rect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        )
        let event = PointerEvent(
            timestamp: 0.4,
            location: NormalizedPoint(x: 0.095, y: 0.4375),
            type: .click
        )

        let normalized = HomeViewModel.normalizedPointerEvents(
            [event],
            coordinateSpace: coordinateSpace,
            target: .window
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].location.x, 0, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].location.y, 1, accuracy: 0.0001)
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

    private func makeViewModel(
        exportSavePanelSelection: ((RecordingProject, EditorViewModel.ExportSavePanelConfiguration) -> URL?)? = nil
    ) -> EditorViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProjectStore(rootDirectoryURL: directory)
        let coordinator = ExportCoordinator(renderer: VideoRenderer(), projectStore: store)
        return EditorViewModel(
            exportCoordinator: coordinator,
            previewRenderer: VideoRenderer(),
            cameraPlanEngine: CameraPlanEngine(),
            projectStore: store,
            preferencesStore: AppPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard),
            exportSavePanelSelection: exportSavePanelSelection
        )
    }

    private func makeProject(
        followStrength: Double,
        aspectRatio: ProjectAspectRatio,
        backgroundPresetID: String = "aurora-air",
        manualZoomSegments: [ManualZoomSegment] = [],
        zoomTrackEdited: Bool = true,
        duration: TimeInterval = 1.0
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
            duration: duration,
            sourceVideoURL: nil,
            events: events,
            cameraKeyframes: keyframes,
            style: ProjectStyle(
                aspectRatio: aspectRatio,
                backgroundPresetID: backgroundPresetID,
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

    private func makeProjectWithPresenterBubble() -> RecordingProject {
        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .bottomRight,
            normalizedSize: 0.26,
            shape: .roundedRect,
            cornerRadius: 22,
            shadowOpacity: 0.32
        )
        let baseProject = makeProject(followStrength: 0.65, aspectRatio: .landscape)
        return baseProject.updating(
            style: ProjectStyle(
                aspectRatio: baseProject.style.aspectRatio,
                backgroundPresetID: baseProject.style.backgroundPresetID,
                cornerRadius: baseProject.style.cornerRadius,
                shadowRadius: baseProject.style.shadowRadius,
                followStrength: baseProject.style.followStrength,
                clickEmphasis: baseProject.style.clickEmphasis,
                padding: baseProject.style.padding,
                presenterBubbleStyle: style
            ),
            cameraKeyframes: baseProject.cameraKeyframes,
            presenterMedia: PresenterMedia(
                sourceVideoURL: URL(fileURLWithPath: "/tmp/presenter.mov"),
                startedAt: Date(timeIntervalSince1970: 10),
                renderOffset: 0,
                naturalSize: CGSize(width: 1280, height: 720)
            )
        )
    }
}
