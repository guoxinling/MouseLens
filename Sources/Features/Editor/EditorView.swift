import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    let project: RecordingProject
    let onBack: () -> Void
    @State private var isDraggingPlayhead = false
    @State private var isDraggingTimeline = false

    private let playheadDragSensitivity: CGFloat = 0.55
    private let trimHandleDragSensitivity: CGFloat = 0.18
    private let zoomSegmentDragSensitivity: CGFloat = 0.72
    private var isTimelineInteractionActive: Bool {
        isDraggingPlayhead || isDraggingTimeline || viewModel.isEditingTimelineTrim || viewModel.isEditingManualZoom
    }

    var body: some View {
        GeometryReader { geometry in
            let displayProject = viewModel.project ?? project
            let isCompactLayout = geometry.size.width < 1040
            let contentHeight = max(geometry.size.height - 61, 1)
            let desktopVerticalPadding: CGFloat = 24
            let desktopTimelineHeight: CGFloat = 214
            let desktopPreviewHeight = max(
                contentHeight - (desktopVerticalPadding * 2) - desktopTimelineHeight - 18,
                360
            )

            VStack(spacing: 0) {
                topBar(project: displayProject)

                Divider()
                    .overlay(AppTheme.panelBorder.opacity(0.5))

                if isCompactLayout {
                    ScrollView {
                        VStack(spacing: 18) {
                            previewArea(project: displayProject, minimumHeight: 320)
                            inspector(project: displayProject, fixedWidth: nil)
                            clipTimeline(project: displayProject)
                        }
                        .padding(20)
                    }
                    .scrollDisabled(isTimelineInteractionActive)
                } else {
                    HStack(spacing: 0) {
                        VStack(spacing: 18) {
                            previewArea(project: displayProject, minimumHeight: 360)
                                .frame(height: desktopPreviewHeight)
                            clipTimeline(project: displayProject)
                                .frame(height: desktopTimelineHeight)
                                .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(desktopVerticalPadding)

                        Divider()
                            .overlay(AppTheme.panelBorder.opacity(0.45))

                        inspector(project: displayProject, fixedWidth: 326)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: project.id) {
            viewModel.configure(for: project)
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            ExportSheetView(exportURL: viewModel.exportURL)
                .frame(width: 520, height: 240)
        }
    }

    private func topBar(project: RecordingProject) -> some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            .help("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(timestampLabel(for: project.trimmedDuration)) clip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer()

            previewStatus(project: project)

            Button {
                viewModel.refreshPreviewVideo()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh preview")
            .disabled(viewModel.previewVideoState.isWorking || project.sourceVideoURL == nil)

            Button {
                Task { await viewModel.export() }
            } label: {
                Label(viewModel.exportState == .exporting ? "Exporting" : "Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.exportState == .exporting)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    @ViewBuilder
    private func previewStatus(project: RecordingProject) -> some View {
        if project.sourceVideoURL != nil, !viewModel.previewVideoState.isWorking {
            Label("Live preview", systemImage: "play.rectangle")
                .foregroundStyle(AppTheme.mutedText)
        } else {
            switch viewModel.previewVideoState {
            case .ready:
                Label("Preview ready", systemImage: "play.rectangle")
                    .foregroundStyle(AppTheme.mutedText)
            case .rendering:
                Label("Preparing preview", systemImage: "clock")
                    .foregroundStyle(AppTheme.mutedText)
            case .updating:
                Label("Updating preview", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(AppTheme.mutedText)
            case .unavailable:
                Label("Static preview", systemImage: "photo")
                    .foregroundStyle(AppTheme.mutedText)
            case .failed:
                Label("Preview failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }

    private func previewArea(project: RecordingProject, minimumHeight: CGFloat) -> some View {
        GeometryReader { geometry in
            let cardWidth = previewCardWidth(
                for: geometry.size,
                aspectRatio: project.style.aspectRatio.editorCanvasAspectRatio
            )
            let cardHeight = previewCardHeight(
                for: cardWidth,
                aspectRatio: project.style.aspectRatio.editorCanvasAspectRatio
            )

            PreviewCanvasView(
                project: project,
                previewImage: viewModel.previewImage,
                isPreviewLoading: viewModel.isPreviewLoading,
                previewVideoURL: viewModel.previewVideoURL,
                previewVideoState: viewModel.previewVideoState,
                prefersStaticPreview: viewModel.prefersStaticPreview,
                showsPlayablePreview: !viewModel.isEditingTimelineTrim,
                trimRange: project.effectiveTrimRange,
                previewDuration: viewModel.previewDuration,
                previewTimestamp: Binding(
                    get: { viewModel.previewOffset },
                    set: { viewModel.updatePreviewTimestamp($0) }
                ),
                onPlaybackTimeChange: { playbackTime in
                    guard !isTimelineInteractionActive else { return }
                    viewModel.updatePreviewTimestamp(playbackTime, refreshPreviewFrame: false)
                },
                onPlaybackEnded: {
                    isDraggingPlayhead = false
                    isDraggingTimeline = false
                    viewModel.updatePreviewTimestamp(0, refreshPreviewFrame: false)
                },
                onRefreshPreviewVideo: {
                    viewModel.refreshPreviewVideo()
                },
                selectedManualZoomSegment: viewModel.isAdjustingManualZoomArea ? viewModel.selectedManualZoomSegment : nil,
                onManualZoomFocusChange: { focus in
                    viewModel.updateSelectedManualZoomFocus(focus)
                }
            )
            .frame(width: cardWidth, height: cardHeight)
            .panelBackground()
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minimumHeight)
    }

    private func previewCardWidth(for availableSize: CGSize, aspectRatio: CGFloat) -> CGFloat {
        let controlChromeHeight: CGFloat = 72
        let availableWidth = max(availableSize.width, 1)
        let availableCanvasHeight = max(availableSize.height - controlChromeHeight, 1)
        return min(availableWidth, availableCanvasHeight * aspectRatio)
    }

    private func previewCardHeight(for width: CGFloat, aspectRatio: CGFloat) -> CGFloat {
        let controlChromeHeight: CGFloat = 72
        return (width / max(aspectRatio, 0.01)) + controlChromeHeight
    }

    private func inspector(project: RecordingProject, fixedWidth: CGFloat?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorSection(title: "Video", systemImage: "rectangle.3.group") {
                    backgroundGrid

                    Picker("Aspect", selection: $viewModel.selectedAspectRatio) {
                        ForEach(ProjectAspectRatio.allCases, id: \.self) { ratio in
                            Text(ratio.label).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)

                    MetricSlider(label: "Padding", value: $viewModel.padding, range: 0.02...0.2)
                    MetricSlider(label: "Corner Radius", value: $viewModel.cornerRadius, range: 0...42)
                }

                inspectorSection(title: "Motion", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    MetricSlider(label: "Zoom Level", value: $viewModel.zoomLevel, range: 0.0...1.0)
                }

                inspectorSection(title: "Zoom", systemImage: "plus.magnifyingglass") {
                    manualZoomInspector(project: project)
                }

                inspectorSection(title: "Export", systemImage: "square.and.arrow.up") {
                    Picker("Preset", selection: $viewModel.exportPreset) {
                        ForEach(ExportPreset.allCases, id: \.self) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }

                    if case .failed(let message) = viewModel.exportState {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : fixedWidth)
        .background(Color.white.opacity(0.04))
    }

    private func inspectorSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: 16)
    }

    @ViewBuilder
    private func manualZoomInspector(project: RecordingProject) -> some View {
        if let segment = viewModel.selectedManualZoomSegment {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    zoomSourceBadge(for: segment.source)
                    Spacer()
                    Text("\(timestampLabel(for: project.clipOffset(forSourceTimestamp: segment.start))) - \(timestampLabel(for: project.clipOffset(forSourceTimestamp: segment.end)))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .font(.system(size: 12))

                if segment.source == .auto {
                    Button {
                        viewModel.convertSelectedZoomSegmentToManual()
                    } label: {
                        Label("Convert to Manual", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!viewModel.canConvertSelectedZoomSegmentToManual)
                } else {
                    MetricSlider(
                        label: "Zoom Level",
                        value: Binding(
                            get: { viewModel.selectedManualZoomSegment?.zoomLevel ?? ManualZoomSegment.defaultZoomLevel },
                            set: { viewModel.updateSelectedManualZoomLevel($0) }
                        ),
                        range: ManualZoomSegment.zoomRange
                    )

                    MetricSlider(
                        label: "Ease",
                        value: Binding(
                            get: { viewModel.selectedManualZoomSegment?.easeInDuration ?? ManualZoomSegment.defaultEaseDuration },
                            set: { viewModel.updateSelectedManualZoomEase($0) }
                        ),
                        range: 0...0.8
                    )

                    HStack(spacing: 10) {
                        Button {
                            viewModel.toggleManualZoomAreaAdjustment()
                        } label: {
                            Label("Set Area", systemImage: "scope")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(viewModel.isAdjustingManualZoomArea ? .orange : .accentColor)
                        .disabled(!viewModel.canAdjustSelectedManualZoomArea)

                        Button {
                            viewModel.focusSelectedManualZoomAtPlayheadCursor()
                            viewModel.stopManualZoomAreaAdjustment()
                        } label: {
                            Label("Cursor", systemImage: "cursorarrow.motionlines")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .font(.system(size: 12, weight: .medium))
                }

                HStack {
                    Spacer()
                    Button {
                        viewModel.stopManualZoomAreaAdjustment()
                        viewModel.deleteSelectedManualZoomSegment()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!viewModel.canDeleteSelectedManualZoomSegment)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("No zoom segments")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    viewModel.addManualZoomSegment()
                } label: {
                    Label("Add Zoom", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func zoomSourceBadge(for source: ZoomSegmentSource) -> some View {
        Text(source == .auto ? "Auto" : "Manual")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(source == .auto ? Color.cyan.opacity(0.55) : Color.orange.opacity(0.62))
            )
    }

    private var backgroundGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ProjectBackgroundStyle.allCases, id: \.self) { style in
                Button {
                    viewModel.selectedBackground = style
                } label: {
                    BackgroundSwatch(
                        style: style,
                        isSelected: viewModel.selectedBackground == style
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clipTimeline(project: RecordingProject) -> some View {
        let timelineDuration = max(project.trimmedDuration, 0.01)
        let segments = project.effectiveClipSegments
        let selectedSegment = viewModel.selectedClipSegment
        let handleColumnWidth: CGFloat = 28
        let handleHitWidth: CGFloat = 52
        let trackInset: CGFloat = handleColumnWidth / 2

        return VStack(alignment: .leading, spacing: 10) {
            timelineHeader(project: project, segments: segments)
            timelineCanvas(
                project: project,
                segments: segments,
                selectedSegment: selectedSegment,
                timelineDuration: timelineDuration,
                handleHitWidth: handleHitWidth,
                trackInset: trackInset
            )
        }
        .padding(18)
        .panelBackground(cornerRadius: 18)
        .frame(minHeight: 214)
    }

    private func timelineHeader(project: RecordingProject, segments: [ProjectTrimRange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Clip", systemImage: "timeline.selection")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(segments.count) segment\(segments.count == 1 ? "" : "s") / \(timestampLabel(for: project.trimmedDuration))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.mutedText)
                Spacer(minLength: 12)
                Text(timestampLabel(for: viewModel.previewOffset))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.mutedText)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.splitClipAtPlayhead()
                } label: {
                    Label("Split", systemImage: "square.split.2x1")
                }
                .disabled(!viewModel.canSplitClip)

                Button {
                    viewModel.deleteSelectedClip()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!viewModel.canDeleteSelectedClip)

                Button {
                    viewModel.resetClips()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Button {
                    viewModel.addManualZoomSegment()
                } label: {
                    Label("Add Zoom", systemImage: "plus.magnifyingglass")
                }

                Spacer()
            }
            .buttonStyle(.borderless)
        }
    }

    private func timelineCanvas(
        project: RecordingProject,
        segments: [ProjectTrimRange],
        selectedSegment: ProjectTrimRange?,
        timelineDuration: TimeInterval,
        handleHitWidth: CGFloat,
        trackInset: CGFloat
    ) -> some View {
        GeometryReader { geometry in
            let plotWidth = max(geometry.size.width - (trackInset * 2), 1)
            let zoomTrackTop: CGFloat = 6
            let zoomTrackHeight: CGFloat = 30
            let trackTop: CGFloat = 48
            let trackHeight = max(geometry.size.height - trackTop - 6, 1)
            let zoomEntries = timelineZoomEntries(for: project)
            let selectedStartOffset = selectedSegment.map { _ in
                clipOffset(forSegmentAt: viewModel.selectedClipSegmentIndex, in: segments)
            }
            let selectedEndOffset = selectedSegment.map { segment in
                (selectedStartOffset ?? 0) + segment.duration
            }

            ZStack(alignment: .topLeading) {
                zoomLane(
                    entries: zoomEntries,
                    timelineDuration: timelineDuration,
                    plotWidth: plotWidth,
                    insetX: trackInset,
                    trackTop: zoomTrackTop,
                    trackHeight: zoomTrackHeight
                )

                clipLane(
                    project: project,
                    segments: segments,
                    timelineDuration: timelineDuration,
                    plotWidth: plotWidth,
                    insetX: trackInset,
                    trackTop: trackTop,
                    trackHeight: trackHeight
                )

                selectedTrimHandles(
                    selectedSegment: selectedSegment,
                    selectedStartOffset: selectedStartOffset,
                    selectedEndOffset: selectedEndOffset,
                    timelineDuration: timelineDuration,
                    plotWidth: plotWidth,
                    insetX: trackInset,
                    handleHitWidth: handleHitWidth,
                    height: geometry.size.height
                )

                playheadHandle(height: geometry.size.height - 4)
                    .position(
                        x: xPosition(
                            forClipOffset: viewModel.previewOffset,
                            timelineDuration: timelineDuration,
                            width: plotWidth,
                            insetX: trackInset
                        ),
                        y: geometry.size.height / 2
                    )
                    .zIndex(40)
                    .allowsHitTesting(false)

                timelineInteractionOverlay(
                    project: project,
                    segments: segments,
                    zoomEntries: zoomEntries,
                    timelineDuration: timelineDuration,
                    plotWidth: plotWidth,
                    insetX: trackInset,
                    zoomTrackTop: zoomTrackTop,
                    zoomTrackHeight: zoomTrackHeight,
                    selectedStartOffset: selectedStartOffset,
                    selectedEndOffset: selectedEndOffset,
                    handleHitWidth: handleHitWidth,
                    size: geometry.size
                )
            }
        }
        .frame(height: 128)
    }

    private func timelineZoomEntries(for project: RecordingProject) -> [TimelineZoomSegment] {
        viewModel.manualZoomSegments.map { segment in
            TimelineZoomSegment(
                id: segment.id,
                startOffset: project.clipOffset(forSourceTimestamp: segment.start),
                endOffset: project.clipOffset(forSourceTimestamp: segment.end),
                zoomLevel: segment.zoomLevel,
                source: segment.source
            )
        }
    }

    private func zoomLane(
        entries: [TimelineZoomSegment],
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        trackTop: CGFloat,
        trackHeight: CGFloat
    ) -> some View {
        let centerY = trackTop + (trackHeight / 2)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .frame(width: plotWidth, height: trackHeight)
                .position(x: insetX + (plotWidth / 2), y: centerY)
                .allowsHitTesting(false)

            ForEach(entries) { entry in
                zoomSegmentView(
                    entry: entry,
                    timelineDuration: timelineDuration,
                    plotWidth: plotWidth,
                    insetX: insetX,
                    centerY: centerY,
                    height: trackHeight
                )
            }
        }
    }

    private func zoomSegmentView(
        entry: TimelineZoomSegment,
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        centerY: CGFloat,
        height: CGFloat
    ) -> some View {
        let startOffset = min(entry.startOffset, entry.endOffset).clamped(to: 0...timelineDuration)
        let endOffset = max(entry.startOffset, entry.endOffset).clamped(to: 0...timelineDuration)
        let startX = xPosition(forClipOffset: startOffset, timelineDuration: timelineDuration, width: plotWidth, insetX: insetX)
        let endX = xPosition(forClipOffset: endOffset, timelineDuration: timelineDuration, width: plotWidth, insetX: insetX)
        let segmentWidth = max(endX - startX, 10)
        let isSelected = entry.id == viewModel.selectedManualZoomSegmentID
        let fillColor = entry.source == .auto ? Color.cyan : Color.orange
        let label = entry.source == .auto ? "Auto" : "Manual"

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? fillColor.opacity(0.72) : fillColor.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.82) : fillColor.opacity(0.55), lineWidth: isSelected ? 1.5 : 1)
                )

            HStack {
                Capsule()
                    .fill(Color.white.opacity(isSelected ? 0.88 : 0.55))
                    .frame(width: 4)
                Spacer(minLength: 8)
                Capsule()
                    .fill(Color.white.opacity(isSelected ? 0.88 : 0.55))
                    .frame(width: 4)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)

            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
        }
        .frame(width: segmentWidth, height: height - 8)
        .position(x: startX + (segmentWidth / 2), y: centerY)
        .allowsHitTesting(false)
    }

    private func clipLane(
        project: RecordingProject,
        segments: [ProjectTrimRange],
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        trackTop: CGFloat,
        trackHeight: CGFloat
    ) -> some View {
        let centerY = trackTop + (trackHeight / 2)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: plotWidth, height: trackHeight)
                .position(x: insetX + (plotWidth / 2), y: centerY)
                .allowsHitTesting(false)

            keyframePath(
                project: project,
                timelineDuration: timelineDuration,
                plotWidth: plotWidth,
                trackHeight: trackHeight,
                insetX: insetX
            )
            .stroke(AppTheme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            .offset(y: trackTop)
            .allowsHitTesting(false)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                clipSegmentView(
                    index: index,
                    segment: segment,
                    segments: segments,
                    timelineDuration: timelineDuration,
                    plotWidth: plotWidth,
                    insetX: insetX,
                    centerY: centerY,
                    trackHeight: trackHeight
                )
            }
        }
    }

    private func clipSegmentView(
        index: Int,
        segment: ProjectTrimRange,
        segments: [ProjectTrimRange],
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        centerY: CGFloat,
        trackHeight: CGFloat
    ) -> some View {
        let startOffset = clipOffset(forSegmentAt: index, in: segments)
        let endOffset = startOffset + segment.duration
        let startX = xPosition(forClipOffset: startOffset, timelineDuration: timelineDuration, width: plotWidth, insetX: insetX)
        let endX = xPosition(forClipOffset: endOffset, timelineDuration: timelineDuration, width: plotWidth, insetX: insetX)
        let segmentWidth = max(endX - startX, 8)
        let isSelected = index == viewModel.selectedClipSegmentIndex

        return RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(isSelected ? AppTheme.accent.opacity(0.24) : Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : Color.white.opacity(0.22), lineWidth: isSelected ? 2 : 1)
            )
            .frame(width: segmentWidth, height: trackHeight)
            .position(x: startX + (segmentWidth / 2), y: centerY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectedTrimHandles(
        selectedSegment: ProjectTrimRange?,
        selectedStartOffset: TimeInterval?,
        selectedEndOffset: TimeInterval?,
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        handleHitWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        if let selectedSegment {
            let startX = xPosition(forClipOffset: selectedStartOffset ?? 0, timelineDuration: timelineDuration, width: plotWidth, insetX: insetX)
            let endX = xPosition(forClipOffset: selectedEndOffset ?? selectedSegment.duration, timelineDuration: timelineDuration, width: plotWidth, insetX: insetX)

            trimHandle(label: "In")
                .frame(width: handleHitWidth, height: height)
                .position(x: startX, y: height / 2)
                .zIndex(30)
                .allowsHitTesting(false)

            trimHandle(label: "Out")
                .frame(width: handleHitWidth, height: height)
                .position(x: endX, y: height / 2)
                .zIndex(30)
                .allowsHitTesting(false)
        }
    }

    private func timelineInteractionOverlay(
        project: RecordingProject,
        segments: [ProjectTrimRange],
        zoomEntries: [TimelineZoomSegment],
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        zoomTrackTop: CGFloat,
        zoomTrackHeight: CGFloat,
        selectedStartOffset: TimeInterval?,
        selectedEndOffset: TimeInterval?,
        handleHitWidth: CGFloat,
        size: CGSize
    ) -> some View {
        TimelineInteractionOverlay(
            timelineDuration: timelineDuration,
            plotWidth: plotWidth,
            insetX: insetX,
            manualZoomSegments: zoomEntries,
            selectedManualZoomSegmentID: viewModel.selectedManualZoomSegmentID,
            zoomLaneFrame: CGRect(x: insetX, y: zoomTrackTop, width: plotWidth, height: zoomTrackHeight),
            playheadOffset: viewModel.previewOffset,
            selectedStartOffset: selectedStartOffset,
            selectedEndOffset: selectedEndOffset,
            handleHitWidth: handleHitWidth,
            playheadHitWidth: 16,
            playheadSensitivity: playheadDragSensitivity,
            trimSensitivity: trimHandleDragSensitivity,
            zoomSegmentSensitivity: zoomSegmentDragSensitivity,
            onSelectClipOffset: { offset in
                viewModel.selectClipSegment(at: segmentIndex(forClipOffset: offset, in: segments))
            },
            onSelectManualZoomSegment: { id in
                viewModel.selectManualZoomSegment(id: id)
            },
            onSeek: { offset in
                isDraggingPlayhead = true
                isDraggingTimeline = true
                viewModel.updatePreviewTimestamp(offset, refreshPreviewFrame: false)
            },
            onBeginTrim: {
                isDraggingTimeline = true
                viewModel.beginTimelineTrimEdit()
            },
            onTrimStart: { offset in
                viewModel.updateTrimStart(project.sourceTimestamp(forClipOffset: offset))
            },
            onTrimEnd: { offset in
                viewModel.updateTrimEnd(project.sourceTimestamp(forClipOffset: offset))
            },
            onBeginManualZoom: {
                isDraggingTimeline = true
                viewModel.beginManualZoomTimelineEdit()
            },
            onMoveManualZoom: { id, startOffset, endOffset in
                viewModel.moveManualZoomSegment(id: id, startClipOffset: startOffset, endClipOffset: endOffset)
            },
            onResizeManualZoomStart: { id, offset in
                viewModel.resizeManualZoomSegmentStart(id: id, startClipOffset: offset)
            },
            onResizeManualZoomEnd: { id, offset in
                viewModel.resizeManualZoomSegmentEnd(id: id, endClipOffset: offset)
            },
            onEndInteraction: {
                isDraggingPlayhead = false
                isDraggingTimeline = false
                viewModel.endTimelineTrimEdit()
                viewModel.endManualZoomTimelineEdit()
            }
        )
        .frame(width: size.width, height: size.height)
        .zIndex(100)
    }

    private func keyframePath(
        project: RecordingProject,
        timelineDuration: Double,
        plotWidth: CGFloat,
        trackHeight: CGFloat,
        insetX: CGFloat
    ) -> Path {
        Path { path in
            let frames = project.cameraKeyframes.filter { frame in
                project.effectiveClipSegments.contains { segment in
                    frame.timestamp >= segment.start && frame.timestamp <= segment.end
                }
            }
            guard !frames.isEmpty else { return }

            for (index, frame) in frames.enumerated() {
                let clipOffset = project.clipOffset(forSourceTimestamp: frame.timestamp)
                let x = xPosition(
                    forClipOffset: clipOffset,
                    timelineDuration: timelineDuration,
                    width: plotWidth,
                    insetX: insetX
                )
                let y = trackHeight * CGFloat(1 - ((frame.zoom - 1.0) / 0.8).clamped(to: 0...1))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func trimHandle(label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(AppTheme.accent)
                .frame(width: 16, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                )
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private func playheadHandle(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.20), radius: 3, y: 1)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: 12, height: 8)
                .shadow(color: .black.opacity(0.20), radius: 3, y: 1)
        }
        .frame(width: 28, height: height)
        .contentShape(Rectangle())
        .help("Drag playhead")
    }

    private func xPosition(
        forClipOffset offset: Double,
        timelineDuration: Double,
        width: CGFloat,
        insetX: CGFloat
    ) -> CGFloat {
        insetX + (width * CGFloat((offset / max(timelineDuration, 0.01)).clamped(to: 0...1)))
    }

    private func clipOffset(forSegmentAt index: Int, in segments: [ProjectTrimRange]) -> Double {
        guard index > 0 else { return 0 }
        return segments.prefix(index).reduce(0) { $0 + $1.duration }
    }

    private func segmentIndex(forClipOffset offset: TimeInterval, in segments: [ProjectTrimRange]) -> Int {
        guard !segments.isEmpty else { return 0 }

        var cursor: TimeInterval = 0
        for (index, segment) in segments.enumerated() {
            let endOffset = cursor + segment.duration
            if offset <= endOffset || index == segments.count - 1 {
                return index
            }
            cursor = endOffset
        }

        return 0
    }

    private func timestampLabel(for timestamp: TimeInterval) -> String {
        let totalCentiseconds = Int((timestamp * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

private struct TimelineZoomSegment: Identifiable {
    let id: UUID
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let zoomLevel: Double
    let source: ZoomSegmentSource
}

struct TimelineTrimHitTester {
    enum Hit: Equatable {
        case trimStart
        case trimEnd
        case playhead
        case track
    }

    static func hit(
        pointX: CGFloat,
        selectedStartOffset: TimeInterval?,
        selectedEndOffset: TimeInterval?,
        playheadOffset: TimeInterval,
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat,
        handleHitWidth: CGFloat,
        playheadHitWidth: CGFloat
    ) -> Hit {
        let startDistance = selectedStartOffset.map {
            abs(pointX - xPosition(forClipOffset: $0, timelineDuration: timelineDuration, plotWidth: plotWidth, insetX: insetX))
        } ?? .greatestFiniteMagnitude
        let endDistance = selectedEndOffset.map {
            abs(pointX - xPosition(forClipOffset: $0, timelineDuration: timelineDuration, plotWidth: plotWidth, insetX: insetX))
        } ?? .greatestFiniteMagnitude

        let playheadDistance = abs(
            pointX - xPosition(
                forClipOffset: playheadOffset,
                timelineDuration: timelineDuration,
                plotWidth: plotWidth,
                insetX: insetX
            )
        )
        if playheadDistance <= playheadHitWidth / 2 {
            return .playhead
        }

        let trimHandleHitWidth = min(handleHitWidth, CGFloat(22))
        let nearestHandleDistance = min(startDistance, endDistance)
        if nearestHandleDistance <= trimHandleHitWidth / 2 {
            return startDistance <= endDistance ? .trimStart : .trimEnd
        }

        return .track
    }

    private static func xPosition(
        forClipOffset offset: TimeInterval,
        timelineDuration: TimeInterval,
        plotWidth: CGFloat,
        insetX: CGFloat
    ) -> CGFloat {
        insetX + (plotWidth * CGFloat((offset / max(timelineDuration, 0.01)).clamped(to: 0...1)))
    }
}

private struct TimelineInteractionOverlay: NSViewRepresentable {
    let timelineDuration: TimeInterval
    let plotWidth: CGFloat
    let insetX: CGFloat
    let manualZoomSegments: [TimelineZoomSegment]
    let selectedManualZoomSegmentID: UUID?
    let zoomLaneFrame: CGRect
    let playheadOffset: TimeInterval
    let selectedStartOffset: TimeInterval?
    let selectedEndOffset: TimeInterval?
    let handleHitWidth: CGFloat
    let playheadHitWidth: CGFloat
    let playheadSensitivity: CGFloat
    let trimSensitivity: CGFloat
    let zoomSegmentSensitivity: CGFloat
    let onSelectClipOffset: (TimeInterval) -> Void
    let onSelectManualZoomSegment: (UUID) -> Void
    let onSeek: (TimeInterval) -> Void
    let onBeginTrim: () -> Void
    let onTrimStart: (TimeInterval) -> Void
    let onTrimEnd: (TimeInterval) -> Void
    let onBeginManualZoom: () -> Void
    let onMoveManualZoom: (UUID, TimeInterval, TimeInterval) -> Void
    let onResizeManualZoomStart: (UUID, TimeInterval) -> Void
    let onResizeManualZoomEnd: (UUID, TimeInterval) -> Void
    let onEndInteraction: () -> Void

    func makeNSView(context: Context) -> TimelineInteractionView {
        TimelineInteractionView()
    }

    func updateNSView(_ nsView: TimelineInteractionView, context: Context) {
        nsView.timelineDuration = timelineDuration
        nsView.plotWidth = plotWidth
        nsView.insetX = insetX
        nsView.manualZoomSegments = manualZoomSegments
        nsView.selectedManualZoomSegmentID = selectedManualZoomSegmentID
        nsView.zoomLaneFrame = zoomLaneFrame
        nsView.playheadOffset = playheadOffset
        nsView.selectedStartOffset = selectedStartOffset
        nsView.selectedEndOffset = selectedEndOffset
        nsView.handleHitWidth = handleHitWidth
        nsView.playheadHitWidth = playheadHitWidth
        nsView.playheadSensitivity = playheadSensitivity
        nsView.trimSensitivity = trimSensitivity
        nsView.zoomSegmentSensitivity = zoomSegmentSensitivity
        nsView.onSelectClipOffset = onSelectClipOffset
        nsView.onSelectManualZoomSegment = onSelectManualZoomSegment
        nsView.onSeek = onSeek
        nsView.onBeginTrim = onBeginTrim
        nsView.onTrimStart = onTrimStart
        nsView.onTrimEnd = onTrimEnd
        nsView.onBeginManualZoom = onBeginManualZoom
        nsView.onMoveManualZoom = onMoveManualZoom
        nsView.onResizeManualZoomStart = onResizeManualZoomStart
        nsView.onResizeManualZoomEnd = onResizeManualZoomEnd
        nsView.onEndInteraction = onEndInteraction
    }
}

private final class TimelineInteractionView: NSView {
    var timelineDuration: TimeInterval = 0.01
    var plotWidth: CGFloat = 1
    var insetX: CGFloat = 0
    var manualZoomSegments: [TimelineZoomSegment] = []
    var selectedManualZoomSegmentID: UUID?
    var zoomLaneFrame: CGRect = .zero
    var playheadOffset: TimeInterval = 0
    var selectedStartOffset: TimeInterval?
    var selectedEndOffset: TimeInterval?
    var handleHitWidth: CGFloat = 52
    var playheadHitWidth: CGFloat = 34
    var playheadSensitivity: CGFloat = 0.55
    var trimSensitivity: CGFloat = 0.20
    var zoomSegmentSensitivity: CGFloat = 0.35
    var onSelectClipOffset: (TimeInterval) -> Void = { _ in }
    var onSelectManualZoomSegment: (UUID) -> Void = { _ in }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onBeginTrim: () -> Void = {}
    var onTrimStart: (TimeInterval) -> Void = { _ in }
    var onTrimEnd: (TimeInterval) -> Void = { _ in }
    var onBeginManualZoom: () -> Void = {}
    var onMoveManualZoom: (UUID, TimeInterval, TimeInterval) -> Void = { _, _, _ in }
    var onResizeManualZoomStart: (UUID, TimeInterval) -> Void = { _, _ in }
    var onResizeManualZoomEnd: (UUID, TimeInterval) -> Void = { _, _ in }
    var onEndInteraction: () -> Void = {}

    private enum DragMode {
        case none
        case seek
        case playhead(startOffset: TimeInterval, startX: CGFloat)
        case trimStart(startOffset: TimeInterval, startX: CGFloat)
        case trimEnd(startOffset: TimeInterval, startX: CGFloat)
        case manualZoomMove(id: UUID, startOffset: TimeInterval, endOffset: TimeInterval, startX: CGFloat)
        case manualZoomStart(id: UUID, startOffset: TimeInterval, startX: CGFloat)
        case manualZoomEnd(id: UUID, endOffset: TimeInterval, startX: CGFloat)
    }

    private var dragMode: DragMode = .none

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        switch hitMode(at: point) {
        case .manualZoomStart(let id, let startOffset):
            onSelectManualZoomSegment(id)
            dragMode = .manualZoomStart(id: id, startOffset: startOffset, startX: point.x)
            onBeginManualZoom()
        case .manualZoomEnd(let id, let endOffset):
            onSelectManualZoomSegment(id)
            dragMode = .manualZoomEnd(id: id, endOffset: endOffset, startX: point.x)
            onBeginManualZoom()
        case .manualZoomMove(let id, let startOffset, let endOffset):
            onSelectManualZoomSegment(id)
            dragMode = .manualZoomMove(id: id, startOffset: startOffset, endOffset: endOffset, startX: point.x)
            onBeginManualZoom()
        case .trimStart:
            if let selectedStartOffset {
                dragMode = .trimStart(startOffset: selectedStartOffset, startX: point.x)
                onBeginTrim()
            }
        case .trimEnd:
            if let selectedEndOffset {
                dragMode = .trimEnd(startOffset: selectedEndOffset, startX: point.x)
                onBeginTrim()
            }
        case .playhead:
            dragMode = .playhead(startOffset: playheadOffset, startX: point.x)
            onSeek(playheadOffset)
        case .track:
            let offset = clipOffset(forX: point.x)
            dragMode = .seek
            onSelectClipOffset(offset)
            onSeek(offset)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .none:
            return
        case .seek:
            onSeek(clipOffset(forX: point.x))
        case .playhead(let startOffset, let startX):
            onSeek(
                dragOffset(
                    from: startOffset,
                    translationX: point.x - startX,
                    sensitivity: playheadSensitivity
                )
            )
        case .trimStart(let startOffset, let startX):
            onTrimStart(
                dragOffset(
                    from: startOffset,
                    translationX: point.x - startX,
                    sensitivity: trimSensitivity
                )
            )
        case .trimEnd(let startOffset, let startX):
            onTrimEnd(
                dragOffset(
                    from: startOffset,
                    translationX: point.x - startX,
                    sensitivity: trimSensitivity
                )
            )
        case .manualZoomMove(let id, let startOffset, let endOffset, let startX):
            let delta = dragDelta(translationX: point.x - startX, sensitivity: zoomSegmentSensitivity)
            let duration = max(endOffset - startOffset, ManualZoomSegment.minimumDuration)
            let nextStart = (startOffset + delta).clamped(to: 0...max(timelineDuration - duration, 0))
            onMoveManualZoom(id, nextStart, nextStart + duration)
        case .manualZoomStart(let id, let startOffset, let startX):
            onResizeManualZoomStart(
                id,
                dragOffset(
                    from: startOffset,
                    translationX: point.x - startX,
                    sensitivity: zoomSegmentSensitivity
                )
            )
        case .manualZoomEnd(let id, let endOffset, let startX):
            onResizeManualZoomEnd(
                id,
                dragOffset(
                    from: endOffset,
                    translationX: point.x - startX,
                    sensitivity: zoomSegmentSensitivity
                )
            )
        }
    }

    override func mouseUp(with event: NSEvent) {
        endInteraction()
    }

    override func mouseExited(with event: NSEvent) {
        // Keep an active drag alive when the pointer temporarily leaves the timeline.
    }

    private enum HitMode {
        case manualZoomStart(UUID, TimeInterval)
        case manualZoomEnd(UUID, TimeInterval)
        case manualZoomMove(UUID, TimeInterval, TimeInterval)
        case trimStart
        case trimEnd
        case playhead
        case track
    }

    private func hitMode(at point: CGPoint) -> HitMode {
        if let zoomHit = manualZoomHitMode(at: point) {
            return zoomHit
        }

        switch TimelineTrimHitTester.hit(
            pointX: point.x,
            selectedStartOffset: selectedStartOffset,
            selectedEndOffset: selectedEndOffset,
            playheadOffset: playheadOffset,
            timelineDuration: timelineDuration,
            plotWidth: plotWidth,
            insetX: insetX,
            handleHitWidth: handleHitWidth,
            playheadHitWidth: playheadHitWidth
        ) {
        case .trimStart:
            return .trimStart
        case .trimEnd:
            return .trimEnd
        case .playhead:
            return .playhead
        case .track:
            return .track
        }
    }

    private func manualZoomHitMode(at point: CGPoint) -> HitMode? {
        guard zoomLaneFrame.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
        let orderedSegments = manualZoomSegments.sorted { lhs, rhs in
            if lhs.id == selectedManualZoomSegmentID { return true }
            if rhs.id == selectedManualZoomSegmentID { return false }
            return lhs.startOffset > rhs.startOffset
        }

        let edgeHitWidth: CGFloat = 28
        var closestEdge: (mode: HitMode, distance: CGFloat)?
        for segment in orderedSegments {
            let startOffset = min(segment.startOffset, segment.endOffset).clamped(to: 0...timelineDuration)
            let endOffset = max(segment.startOffset, segment.endOffset).clamped(to: 0...timelineDuration)
            let startX = xPosition(forClipOffset: startOffset)
            let endX = xPosition(forClipOffset: endOffset)
            let startDistance = abs(point.x - startX)
            let endDistance = abs(point.x - endX)

            if startDistance <= edgeHitWidth {
                if closestEdge == nil || startDistance < (closestEdge?.distance ?? .greatestFiniteMagnitude) {
                    closestEdge = (.manualZoomStart(segment.id, startOffset), startDistance)
                }
            }

            if endDistance <= edgeHitWidth {
                if closestEdge == nil || endDistance < (closestEdge?.distance ?? .greatestFiniteMagnitude) {
                    closestEdge = (.manualZoomEnd(segment.id, endOffset), endDistance)
                }
            }
        }

        if let closestEdge {
            return closestEdge.mode
        }

        if let segment = orderedSegments.first(where: { segment in
            let startX = xPosition(forClipOffset: min(segment.startOffset, segment.endOffset))
            let endX = xPosition(forClipOffset: max(segment.startOffset, segment.endOffset))
            return point.x >= startX && point.x <= endX
        }) {
            return .manualZoomMove(
                segment.id,
                min(segment.startOffset, segment.endOffset).clamped(to: 0...timelineDuration),
                max(segment.startOffset, segment.endOffset).clamped(to: 0...timelineDuration)
            )
        }

        return nil
    }

    private func endInteraction() {
        guard case .none = dragMode else {
            dragMode = .none
            onEndInteraction()
            return
        }
    }

    private func clipOffset(forX x: CGFloat) -> TimeInterval {
        let progress = Double(((x - insetX) / max(plotWidth, 1)).clamped(to: 0...1))
        return (progress * timelineDuration).clamped(to: 0...timelineDuration)
    }

    private func xPosition(forClipOffset offset: TimeInterval) -> CGFloat {
        insetX + (plotWidth * CGFloat((offset / max(timelineDuration, 0.01)).clamped(to: 0...1)))
    }

    private func dragOffset(
        from startOffset: TimeInterval,
        translationX: CGFloat,
        sensitivity: CGFloat
    ) -> TimeInterval {
        (startOffset + dragDelta(translationX: translationX, sensitivity: sensitivity))
            .clamped(to: 0...timelineDuration)
    }

    private func dragDelta(translationX: CGFloat, sensitivity: CGFloat) -> TimeInterval {
        let deltaProgress = (translationX / max(plotWidth, 1)) * sensitivity
        return Double(deltaProgress) * timelineDuration
    }
}

private extension View {
    func panelBackground(cornerRadius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.075))
                .strokeBorder(AppTheme.panelBorder, lineWidth: 1)
        )
    }
}

private struct BackgroundSwatch: View {
    let style: ProjectBackgroundStyle
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.gradient)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                    .frame(width: 54, height: 31)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white, AppTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(7)
                }
            }
            .frame(height: 58)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            )

            Text(style.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : AppTheme.mutedText)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.18) : Color.white.opacity(0.04))
        )
    }
}

private extension ProjectAspectRatio {
    var editorCanvasAspectRatio: CGFloat {
        switch self {
        case .landscape:
            16.0 / 9.0
        case .portrait:
            9.0 / 16.0
        case .square:
            1.0
        }
    }
}
