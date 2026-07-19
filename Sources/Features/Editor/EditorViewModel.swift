import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    struct ExportSavePanelConfiguration: Equatable {
        let title: String
        let message: String
        let allowedContentTypes: [UTType]
        let defaultFilename: String
        let requiredPathExtension: String
    }

    @Published private(set) var project: RecordingProject?
    @Published var zoomLevel = 0.54 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published private(set) var followStrength = 0.72
    @Published private(set) var clickEmphasis = 0.54
    @Published var padding = 0.04 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var cornerRadius = 10.35 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var selectedBackgroundPresetID = BackgroundPresetCatalog.defaultPresetID {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var selectedAspectRatio: ProjectAspectRatio = .landscape {
        didSet { handleStyleChange(updateExportPreset: true) }
    }
    @Published var exportPreset: ExportPreset = .standardLandscape
    @Published private(set) var exportConfiguration = ExportConfiguration.recommended(for: .landscape)
    @Published private(set) var isExportConfigurationModified = false
    @Published var exportState: ExportState = .idle
    @Published var exportURL: URL?
    @Published var showExportSheet = false
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var isPreviewLoading = false
    @Published private(set) var previewVideoURL: URL?
    @Published private(set) var previewVideoState: PreviewVideoState = .unavailable
    @Published private(set) var prefersStaticPreview = false
    @Published private(set) var previewTimestamp = 0.0
    @Published private(set) var clipSegments: [ProjectTrimRange] = []
    @Published private(set) var selectedClipSegmentIndex = 0
    @Published private(set) var trimStart = 0.0
    @Published private(set) var trimEnd = 0.0
    @Published private(set) var isEditingTimelineTrim = false
    @Published private(set) var manualZoomSegments: [ManualZoomSegment] = []
    @Published private(set) var selectedManualZoomSegmentID: UUID?
    @Published private(set) var isEditingManualZoom = false
    @Published private(set) var isAdjustingManualZoomArea = false
    @Published private(set) var isPresenterBubbleEnabled = PresenterBubbleStyle.defaultValue.isEnabled
    @Published private(set) var presenterBubblePosition = PresenterBubbleStyle.defaultValue.position
    @Published private(set) var presenterBubbleSize = PresenterBubbleStyle.defaultValue.normalizedSize
    @Published private(set) var presenterBubbleCornerRadiusRatio = PresenterBubbleStyle.defaultValue.cornerRadiusRatio

    private let exportCoordinator: ExportCoordinator
    private let previewRenderer: any ProjectPreviewRendering
    private let cameraPlanEngine: CameraPlanEngine
    private let projectStore: ProjectStore
    private let preferencesStore: AppPreferencesStore
    private let exportSavePanelSelection: ((RecordingProject, ExportSavePanelConfiguration) -> URL?)?
    private let baseZoom = 1.0
    private let clickDuration = 0.6
    private let gifWarningDurationThreshold = 12.0
    private let minimumTrimDuration = 0.2
    private let minimumManualZoomDuration = ManualZoomSegment.minimumDuration
    private var sourceProject: RecordingProject?
    private var isApplyingConfiguration = false
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingPreviewTask: Task<Void, Never>?
    private var pendingPreviewVideoTask: Task<Void, Never>?
    private var previewVideoGeneration = 0
    private var needsPreviewVideoAfterTrimEdit = false
    private var needsPreviewVideoAfterManualZoomEdit = false

    init(
        exportCoordinator: ExportCoordinator,
        previewRenderer: any ProjectPreviewRendering,
        cameraPlanEngine: CameraPlanEngine,
        projectStore: ProjectStore,
        preferencesStore: AppPreferencesStore,
        exportSavePanelSelection: ((RecordingProject, ExportSavePanelConfiguration) -> URL?)? = nil
    ) {
        self.exportCoordinator = exportCoordinator
        self.previewRenderer = previewRenderer
        self.cameraPlanEngine = cameraPlanEngine
        self.projectStore = projectStore
        self.preferencesStore = preferencesStore
        self.exportSavePanelSelection = exportSavePanelSelection
    }

    deinit {
        pendingSaveTask?.cancel()
        pendingPreviewTask?.cancel()
        pendingPreviewVideoTask?.cancel()
    }

    func configure(for project: RecordingProject) {
        pendingSaveTask?.cancel()
        pendingPreviewTask?.cancel()
        pendingPreviewVideoTask?.cancel()
        sourceProject = project
        self.project = project
        isApplyingConfiguration = true
        zoomLevel = Self.zoomLevel(from: project.style)
        let motionSettings = Self.motionSettings(for: zoomLevel)
        followStrength = motionSettings.followStrength
        clickEmphasis = motionSettings.clickEmphasis
        padding = project.style.padding
        cornerRadius = project.style.cornerRadius
        selectedBackgroundPresetID = project.style.backgroundPresetID
        selectedAspectRatio = project.style.aspectRatio
        trimStart = project.effectiveTrimRange.start
        trimEnd = project.effectiveTrimRange.end
        exportPreset = ExportPreset.defaultPreset(for: project.style.aspectRatio)
        exportConfiguration = .recommended(for: project.style.aspectRatio)
        isExportConfigurationModified = false
        exportState = .idle
        exportURL = nil
        showExportSheet = false
        previewImage = nil
        isPreviewLoading = false
        previewVideoURL = nil
        previewVideoState = .unavailable
        prefersStaticPreview = false
        isEditingTimelineTrim = false
        isEditingManualZoom = false
        isAdjustingManualZoomArea = false
        syncPresenterBubbleState(with: project.style.presenterBubbleStyle)
        needsPreviewVideoAfterTrimEdit = false
        needsPreviewVideoAfterManualZoomEdit = false
        syncClipState(with: project.effectiveClipSegments, selectedIndex: 0)
        syncManualZoomState(with: project.manualZoomSegments, selectedID: nil)
        previewTimestamp = defaultPreviewTimestamp(for: project)
        isApplyingConfiguration = false
        schedulePreview(for: project)
    }

    func export() async {
        guard let project else { return }
        guard exportConfiguration.format.isAvailable else {
            exportState = .failed("This export format is not available yet.")
            return
        }
        guard let destinationURL = presentExportSavePanel(for: project, configuration: exportConfiguration) else {
            exportState = .idle
            return
        }

        exportState = .exporting
        do {
            let url = try await exportCoordinator.exportVideo(
                for: project,
                configuration: exportConfiguration,
                destinationURL: destinationURL
            )
            exportURL = url
            exportState = .finished(url)
            if preferencesStore.autoRevealExportInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            showExportSheet = true
        } catch {
            exportState = .failed(Self.describeExportError(error))
        }
    }

    private func presentExportSavePanel(
        for project: RecordingProject,
        configuration: ExportConfiguration
    ) -> URL? {
        let panelConfiguration = Self.exportSavePanelConfiguration(for: project, configuration: configuration)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = panelConfiguration.title
        panel.message = panelConfiguration.message
        panel.nameFieldStringValue = panelConfiguration.defaultFilename
        panel.allowedContentTypes = panelConfiguration.allowedContentTypes
        panel.directoryURL = defaultExportDirectoryURL()

        let selectedURL: URL?
        if let exportSavePanelSelection {
            selectedURL = exportSavePanelSelection(project, panelConfiguration)
        } else if panel.runModal() == .OK {
            selectedURL = panel.url
        } else {
            selectedURL = nil
        }

        guard let selectedURL else {
            return nil
        }

        return Self.normalizedExportDestinationURL(
            selectedURL,
            requiredPathExtension: panelConfiguration.requiredPathExtension
        )
    }

    static func exportSavePanelConfiguration(
        for project: RecordingProject,
        configuration: ExportConfiguration
    ) -> ExportSavePanelConfiguration {
        let defaultFilename = ExportCoordinator.exportFilename(for: project, configuration: configuration)

        switch configuration.format {
        case .mp4:
            return ExportSavePanelConfiguration(
                title: "Export MP4",
                message: "Choose where MouseLens should save the exported video.",
                allowedContentTypes: [.mpeg4Movie],
                defaultFilename: defaultFilename,
                requiredPathExtension: ExportFormat.mp4.fileExtension
            )
        case .gif:
            return ExportSavePanelConfiguration(
                title: "Export GIF",
                message: "Choose where MouseLens should save the exported GIF.",
                allowedContentTypes: [.gif],
                defaultFilename: defaultFilename,
                requiredPathExtension: ExportFormat.gif.fileExtension
            )
        }
    }

    static func normalizedExportDestinationURL(
        _ selectedURL: URL,
        requiredPathExtension: String
    ) -> URL {
        guard selectedURL.pathExtension.lowercased() != requiredPathExtension.lowercased() else {
            return selectedURL
        }

        let baseURL = selectedURL.pathExtension.isEmpty ? selectedURL : selectedURL.deletingPathExtension()
        return baseURL.appendingPathExtension(requiredPathExtension)
    }

    var exportButtonLabel: String {
        switch exportConfiguration.format {
        case .mp4: "Export MP4"
        case .gif: "Export GIF"
        }
    }

    var estimatedExportByteCount: Int64 {
        ExportSizeEstimator.estimatedByteCount(
            for: exportConfiguration,
            aspectRatio: project?.style.aspectRatio ?? selectedAspectRatio,
            duration: project?.trimmedDuration ?? 0
        )
    }

    var estimatedExportSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: estimatedExportByteCount, countStyle: .file)
    }

    var estimatedExportSizeCaption: String {
        exportConfiguration.format == .gif ? "Approx. size" : "Estimated size"
    }

    var showsGIFDurationWarning: Bool {
        exportConfiguration.format == .gif && (project?.trimmedDuration ?? 0) > gifWarningDurationThreshold
    }

    var gifDurationWarningText: String {
        "Long GIFs can become large. Trim the clip if you want a smaller file."
    }

    var canExportSelectedFormat: Bool {
        exportConfiguration.format.isAvailable
    }

    var canEditPresenterBubble: Bool {
        project?.presenterMedia != nil
    }

    var exportUnavailableMessage: String? {
        nil
    }

    func updatePresenterBubbleEnabled(_ isEnabled: Bool) {
        updatePresenterBubbleStyle { style in
            PresenterBubbleStyle(
                isEnabled: isEnabled,
                normalizedCenter: style.normalizedCenter,
                normalizedSize: style.normalizedSize,
                cornerRadiusRatio: style.cornerRadiusRatio,
                shadowOpacity: style.shadowOpacity,
                source: style.source
            )
        }
    }

    func updatePresenterBubblePosition(_ position: PresenterBubblePosition) {
        updatePresenterBubbleStyle { style in
            PresenterBubbleStyle(
                isEnabled: style.isEnabled,
                normalizedCenter: PresenterBubbleStyle.defaultCenter(for: position),
                normalizedSize: style.normalizedSize,
                cornerRadiusRatio: style.cornerRadiusRatio,
                shadowOpacity: style.shadowOpacity,
                source: style.source
            )
        }
    }

    func updatePresenterBubbleSize(_ size: Double) {
        updatePresenterBubbleStyle { style in
            PresenterBubbleStyle(
                isEnabled: style.isEnabled,
                normalizedCenter: style.normalizedCenter,
                normalizedSize: size.clamped(to: 0.12...0.4),
                cornerRadiusRatio: style.cornerRadiusRatio,
                shadowOpacity: style.shadowOpacity,
                source: style.source
            )
        }
    }

    func updatePresenterBubbleCornerRadiusRatio(_ ratio: Double) {
        updatePresenterBubbleStyle { style in
            PresenterBubbleStyle(
                isEnabled: style.isEnabled,
                normalizedCenter: style.normalizedCenter,
                normalizedSize: style.normalizedSize,
                cornerRadiusRatio: ratio.clamped(to: 0...0.5),
                shadowOpacity: style.shadowOpacity,
                source: style.source
            )
        }
    }

    func updateExportFormat(_ format: ExportFormat) {
        guard exportConfiguration.format != format else { return }
        exportConfiguration = .recommended(for: selectedAspectRatio, format: format)
        isExportConfigurationModified = false
        exportState = .idle
    }

    func updateExportResolution(_ value: ExportResolution) {
        updateExportConfiguration {
            if ExportConfiguration.allowedResolutions(for: $0.format).contains(value) {
                $0.resolution = value
            }
        }
    }

    func updateExportFrameRate(_ value: ExportFrameRate) {
        updateExportConfiguration {
            if ExportConfiguration.allowedFrameRates(for: $0.format).contains(value) {
                $0.frameRate = value
            }
        }
    }

    func updateExportQuality(_ value: ExportQuality) {
        updateExportConfiguration { $0.quality = value }
    }

    func updateExportIncludesCursor(_ value: Bool) {
        updateExportConfiguration { $0.includesCursor = value }
    }

    func updateExportIncludesClickFeedback(_ value: Bool) {
        updateExportConfiguration { $0.includesClickFeedback = value }
    }

    func resetExportConfiguration() {
        exportConfiguration = .recommended(for: selectedAspectRatio, format: exportConfiguration.format)
        isExportConfigurationModified = false
        exportState = .idle
    }

    private func updateExportConfiguration(_ change: (inout ExportConfiguration) -> Void) {
        change(&exportConfiguration)
        if exportConfiguration.format == .gif {
            exportConfiguration.quality = .balanced
            exportConfiguration.includesCursor = true
            exportConfiguration.includesClickFeedback = true
        }
        isExportConfigurationModified = exportConfiguration != .recommended(
            for: selectedAspectRatio,
            format: exportConfiguration.format
        )
        exportState = .idle
    }

    private func defaultExportDirectoryURL() -> URL {
        let fileManager = FileManager.default
        if let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first {
            return moviesDirectory
        }

        if let desktopDirectory = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first {
            return desktopDirectory
        }

        return fileManager.homeDirectoryForCurrentUser
    }

    private static func describeExportError(_ error: Error) -> String {
        let nsError = error as NSError
        var fragments = [nsError.localizedDescription]

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlyingError.localizedDescription != nsError.localizedDescription {
            fragments.append("Underlying: \(underlyingError.localizedDescription)")
        }

        fragments.append("[\(nsError.domain) \(nsError.code)]")
        return fragments.joined(separator: " ")
    }

    var previewDuration: Double {
        project?.trimmedDuration ?? sourceProject?.trimmedDuration ?? 0
    }

    var previewOffset: Double {
        guard let project else { return 0 }
        return project.clipOffset(forSourceTimestamp: previewTimestamp)
    }

    var trimUpperBound: Double {
        max(project?.duration ?? sourceProject?.duration ?? 0, 0)
    }

    func updatePreviewTimestamp(_ value: Double) {
        updatePreviewTimestamp(value, refreshPreviewFrame: true)
    }

    func updatePreviewTimestamp(_ value: Double, refreshPreviewFrame: Bool) {
        guard let project else { return }
        let absoluteTimestamp = project.sourceTimestamp(forClipOffset: value)
        guard abs(absoluteTimestamp - previewTimestamp) > 0.0001 else { return }
        previewTimestamp = absoluteTimestamp

        selectedClipSegmentIndex = segmentIndex(containing: absoluteTimestamp, in: currentClipSegments)
        syncSelectedTrimState()
        schedulePreviewForTimestampChange(for: project, refreshPreviewFrame: refreshPreviewFrame)
    }

    func updatePreviewAbsoluteTimestamp(_ value: Double) {
        updatePreviewAbsoluteTimestamp(value, refreshPreviewFrame: true)
    }

    func updatePreviewAbsoluteTimestamp(_ value: Double, refreshPreviewFrame: Bool) {
        guard let project else { return }
        let absoluteTimestamp = project.nearestClipSourceTimestamp(to: value)
        updatePreviewTimestamp(
            project.clipOffset(forSourceTimestamp: absoluteTimestamp),
            refreshPreviewFrame: refreshPreviewFrame
        )
    }

    func refreshPreviewVideo() {
        guard let project else { return }
        schedulePreviewVideo(for: project, debounceNanoseconds: 0)
    }

    func beginTimelineTrimEdit() {
        guard !isEditingTimelineTrim else { return }

        isEditingTimelineTrim = true
        needsPreviewVideoAfterTrimEdit = false
        pendingPreviewVideoTask?.cancel()
        previewVideoGeneration += 1

        if previewVideoState.isWorking {
            previewVideoState = previewVideoURL == nil ? .unavailable : .ready
        }
    }

    func endTimelineTrimEdit() {
        guard isEditingTimelineTrim else { return }

        isEditingTimelineTrim = false
        needsPreviewVideoAfterTrimEdit = false
    }

    func updateTrimStart(_ value: Double) {
        applyTrimChange(start: value, end: nil)
    }

    func updateTrimEnd(_ value: Double) {
        applyTrimChange(start: nil, end: value)
    }

    var selectedClipSegment: ProjectTrimRange? {
        guard currentClipSegments.indices.contains(selectedClipSegmentIndex) else { return currentClipSegments.first }
        return currentClipSegments[selectedClipSegmentIndex]
    }

    var selectedManualZoomSegment: ManualZoomSegment? {
        guard let selectedManualZoomSegmentID else { return nil }
        return manualZoomSegments.first { $0.id == selectedManualZoomSegmentID }
    }

    var selectedZoomSegmentSource: ZoomSegmentSource? {
        selectedManualZoomSegment?.source
    }

    var canDeleteSelectedManualZoomSegment: Bool {
        selectedManualZoomSegment != nil
    }

    var canAdjustSelectedManualZoomArea: Bool {
        selectedManualZoomSegment?.source == .manual
    }

    var canConvertSelectedZoomSegmentToManual: Bool {
        selectedManualZoomSegment?.source == .auto
    }

    var canSplitClip: Bool {
        guard let selectedClipSegment else { return false }
        return (previewTimestamp - selectedClipSegment.start) >= minimumTrimDuration
            && (selectedClipSegment.end - previewTimestamp) >= minimumTrimDuration
    }

    var canDeleteSelectedClip: Bool {
        currentClipSegments.count > 1
    }

    var canSplitTimelineSelection: Bool {
        if selectedManualZoomSegment != nil {
            return canSplitSelectedManualZoomSegment
        }
        return canSplitClip
    }

    var canDeleteTimelineSelection: Bool {
        if selectedManualZoomSegment != nil {
            return canDeleteSelectedManualZoomSegment
        }
        return canDeleteSelectedClip
    }

    var timelineSelectionLabel: String {
        selectedManualZoomSegment == nil ? "Clip" : "Zoom"
    }

    var canSplitSelectedManualZoomSegment: Bool {
        guard let segment = selectedManualZoomSegment else { return false }
        let splitPoint = previewTimestamp.clamped(to: segment.start...segment.end)
        return splitPoint - segment.start >= minimumManualZoomDuration
            && segment.end - splitPoint >= minimumManualZoomDuration
    }

    func selectClipSegment(at index: Int) {
        let segments = currentClipSegments
        guard segments.indices.contains(index) else { return }
        selectedManualZoomSegmentID = nil
        isAdjustingManualZoomArea = false
        selectedClipSegmentIndex = index
        syncSelectedTrimState()
        previewTimestamp = segments[index].start

        guard let project else { return }
        schedulePreview(for: project)
    }

    func splitClipAtPlayhead() {
        guard let workingProject = project ?? sourceProject else { return }
        var segments = currentClipSegments
        let index = segmentIndex(containing: previewTimestamp, in: segments)
        guard segments.indices.contains(index) else { return }

        let segment = segments[index]
        let splitPoint = previewTimestamp.clamped(to: segment.start...segment.end)
        guard splitPoint - segment.start >= minimumTrimDuration,
              segment.end - splitPoint >= minimumTrimDuration else {
            return
        }

        segments[index] = ProjectTrimRange(start: segment.start, end: splitPoint)
        segments.insert(ProjectTrimRange(start: splitPoint, end: segment.end), at: index + 1)
        applyClipSegments(segments, selectedIndex: index + 1, workingProject: workingProject)
    }

    func splitTimelineSelectionAtPlayhead() {
        if selectedManualZoomSegment != nil {
            splitSelectedManualZoomSegmentAtPlayhead()
        } else {
            splitClipAtPlayhead()
        }
    }

    func deleteSelectedClip() {
        guard let workingProject = project ?? sourceProject, canDeleteSelectedClip else { return }

        var segments = currentClipSegments
        guard segments.indices.contains(selectedClipSegmentIndex) else { return }
        segments.remove(at: selectedClipSegmentIndex)
        let nextIndex = min(selectedClipSegmentIndex, max(segments.count - 1, 0))
        applyClipSegments(segments, selectedIndex: nextIndex, workingProject: workingProject)
    }

    func deleteTimelineSelection() {
        if selectedManualZoomSegment != nil {
            deleteSelectedManualZoomSegment()
        } else {
            deleteSelectedClip()
        }
    }

    func resetClips() {
        guard let workingProject = project ?? sourceProject else { return }

        let fullSegment = ProjectTrimRange(start: 0, end: workingProject.duration)
        applyClipSegments([fullSegment], selectedIndex: 0, workingProject: workingProject)
    }

    func addManualZoomSegment() {
        guard let workingProject = project ?? sourceProject else { return }

        let timelineDuration = max(workingProject.trimmedDuration, 0)
        guard timelineDuration > 0 else { return }

        let startOffset = previewOffset.clamped(to: 0...timelineDuration)
        let proposedEndOffset = (startOffset + ManualZoomSegment.defaultDuration).clamped(to: 0...timelineDuration)
        let endOffset: TimeInterval
        let adjustedStartOffset: TimeInterval
        if proposedEndOffset - startOffset >= minimumManualZoomDuration {
            adjustedStartOffset = startOffset
            endOffset = proposedEndOffset
        } else {
            endOffset = timelineDuration
            adjustedStartOffset = max(0, endOffset - ManualZoomSegment.defaultDuration)
        }

        let sourceStart = workingProject.sourceTimestamp(forClipOffset: adjustedStartOffset)
        let sourceEnd = max(
            workingProject.sourceTimestamp(forClipOffset: endOffset),
            sourceStart + minimumManualZoomDuration
        ).clamped(to: 0...workingProject.duration)

        let segment = ManualZoomSegment(
            start: sourceStart,
            end: sourceEnd,
            focus: defaultManualZoomFocus(at: previewTimestamp, in: workingProject),
            source: .manual
        )
        applyManualZoomSegments(manualZoomSegments + [segment], selectedID: segment.id, workingProject: workingProject)
    }

    func selectManualZoomSegment(id: UUID) {
        guard manualZoomSegments.contains(where: { $0.id == id }) else { return }
        selectedManualZoomSegmentID = id
    }

    func deleteSelectedManualZoomSegment() {
        guard let selectedManualZoomSegmentID, let workingProject = project ?? sourceProject else { return }
        let segments = manualZoomSegments.filter { $0.id != selectedManualZoomSegmentID }
        isAdjustingManualZoomArea = false
        applyManualZoomSegments(segments, selectedID: segments.first?.id, workingProject: workingProject)
    }

    func splitSelectedManualZoomSegmentAtPlayhead() {
        guard let selectedManualZoomSegmentID,
              let workingProject = project ?? sourceProject,
              let index = manualZoomSegments.firstIndex(where: { $0.id == selectedManualZoomSegmentID }) else {
            return
        }

        let segment = manualZoomSegments[index]
        let splitPoint = previewTimestamp.clamped(to: segment.start...segment.end)
        guard splitPoint - segment.start >= minimumManualZoomDuration,
              segment.end - splitPoint >= minimumManualZoomDuration else {
            return
        }

        let left = segment.updating(end: splitPoint)
        let right = ManualZoomSegment(
            start: splitPoint,
            end: segment.end,
            focus: segment.focus,
            zoomLevel: segment.zoomLevel,
            easeInDuration: min(segment.easeInDuration, max(segment.end - splitPoint, 0) / 2),
            easeOutDuration: min(segment.easeOutDuration, max(segment.end - splitPoint, 0) / 2),
            source: segment.source
        )

        var segments = manualZoomSegments
        segments[index] = left
        segments.insert(right, at: index + 1)
        isAdjustingManualZoomArea = false
        applyManualZoomSegments(segments, selectedID: right.id, workingProject: workingProject)
    }

    func toggleManualZoomAreaAdjustment() {
        guard canAdjustSelectedManualZoomArea else {
            isAdjustingManualZoomArea = false
            return
        }

        isAdjustingManualZoomArea.toggle()
    }

    func stopManualZoomAreaAdjustment() {
        isAdjustingManualZoomArea = false
    }

    func updateSelectedManualZoomLevel(_ value: Double) {
        updateSelectedManualZoomSegment { segment in
            segment.updating(zoomLevel: value, source: .manual)
        }
    }

    func updateSelectedManualZoomFocus(_ focus: NormalizedPoint) {
        updateSelectedManualZoomSegment { segment in
            segment.updating(focus: focus, source: .manual)
        }
    }

    func updateSelectedManualZoomEase(_ value: Double) {
        updateSelectedManualZoomSegment { segment in
            let duration = segment.duration
            let safeEase = value.clamped(to: 0...max(duration / 2, 0))
            return segment.updating(easeInDuration: safeEase, easeOutDuration: safeEase, source: .manual)
        }
    }

    func focusSelectedManualZoomAtPlayheadCursor() {
        guard let workingProject = project ?? sourceProject else { return }
        updateSelectedManualZoomFocus(defaultManualZoomFocus(at: previewTimestamp, in: workingProject))
    }

    func convertSelectedZoomSegmentToManual() {
        updateSelectedManualZoomSegment { segment in
            segment.updating(source: .manual)
        }
    }

    func beginManualZoomTimelineEdit() {
        guard !isEditingManualZoom else { return }

        isEditingManualZoom = true
        needsPreviewVideoAfterManualZoomEdit = false
        pendingPreviewVideoTask?.cancel()
        previewVideoGeneration += 1

        if previewVideoState.isWorking {
            previewVideoState = previewVideoURL == nil ? .unavailable : .ready
        }
    }

    func endManualZoomTimelineEdit() {
        guard isEditingManualZoom else { return }

        isEditingManualZoom = false
        needsPreviewVideoAfterManualZoomEdit = false
    }

    func moveManualZoomSegment(id: UUID, startClipOffset: TimeInterval, endClipOffset: TimeInterval) {
        updateManualZoomSegmentTiming(id: id, startClipOffset: startClipOffset, endClipOffset: endClipOffset)
    }

    func resizeManualZoomSegmentStart(id: UUID, startClipOffset: TimeInterval) {
        guard let segment = manualZoomSegments.first(where: { $0.id == id }),
              let workingProject = project ?? sourceProject else { return }
        let endOffset = workingProject.clipOffset(forSourceTimestamp: segment.end)
        updateManualZoomSegmentTiming(id: id, startClipOffset: startClipOffset, endClipOffset: endOffset)
    }

    func resizeManualZoomSegmentEnd(id: UUID, endClipOffset: TimeInterval) {
        guard let segment = manualZoomSegments.first(where: { $0.id == id }),
              let workingProject = project ?? sourceProject else { return }
        let startOffset = workingProject.clipOffset(forSourceTimestamp: segment.start)
        updateManualZoomSegmentTiming(id: id, startClipOffset: startOffset, endClipOffset: endClipOffset)
    }

    private func handleStyleChange(updateExportPreset: Bool) {
        guard !isApplyingConfiguration, let sourceProject else { return }
        let currentProject = project ?? sourceProject
        let motionSettings = Self.motionSettings(for: zoomLevel)
        followStrength = motionSettings.followStrength
        clickEmphasis = motionSettings.clickEmphasis

        let style = ProjectStyle(
            aspectRatio: selectedAspectRatio,
            backgroundPresetID: selectedBackgroundPresetID,
            cornerRadius: cornerRadius,
            shadowRadius: 0,
            followStrength: motionSettings.followStrength,
            clickEmphasis: motionSettings.clickEmphasis,
            padding: padding,
            presenterBubbleStyle: currentProject.style.presenterBubbleStyle
        )

        let keyframes = cameraPlanEngine.makePlan(
            from: sourceProject.events,
            baseZoom: baseZoom,
            followStrength: style.followStrength,
            clickRule: ClickEmphasisRule(boost: style.clickEmphasis, duration: clickDuration)
        )
        let duration = max(sourceProject.duration, keyframes.last?.timestamp ?? sourceProject.duration)
        let updatedProject = currentProject.updating(
            style: style,
            cameraKeyframes: keyframes,
            duration: duration,
            trimRange: currentTrimRange,
            clipSegments: currentClipSegments
        )

        project = updatedProject
        exportState = .idle
        syncClipState(with: updatedProject.effectiveClipSegments, selectedIndex: selectedClipSegmentIndex)
        previewTimestamp = updatedProject.nearestClipSourceTimestamp(to: previewTimestamp)

        if updateExportPreset {
            exportPreset = ExportPreset.defaultPreset(for: style.aspectRatio)
        }

        scheduleSave(for: updatedProject)
        pendingPreviewTask?.cancel()
        isPreviewLoading = false
        prefersStaticPreview = updatedProject.sourceVideoURL != nil
    }

    private struct MotionSettings {
        let followStrength: Double
        let clickEmphasis: Double
    }

    private static func motionSettings(for zoomLevel: Double) -> MotionSettings {
        let level = zoomLevel.clamped(to: 0...1)
        return MotionSettings(
            followStrength: 0.68 + (level * 0.14),
            clickEmphasis: level
        )
    }

    private static func zoomLevel(from style: ProjectStyle) -> Double {
        style.clickEmphasis.clamped(to: 0...1)
    }

    private func scheduleSave(for project: RecordingProject) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [projectStore] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            try? projectStore.save(project: project)
        }
    }

    private func schedulePreview(
        for project: RecordingProject,
        debounceNanoseconds: UInt64 = 120_000_000
    ) {
        pendingPreviewTask?.cancel()

        guard project.sourceVideoURL != nil else {
            previewImage = nil
            isPreviewLoading = false
            return
        }

        let timestamp = project.nearestClipSourceTimestamp(to: previewTimestamp)
        let preset = exportPreset
        isPreviewLoading = true

        pendingPreviewTask = Task { [previewRenderer] in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            let image = try? await previewRenderer.makePreviewImage(
                for: project,
                preset: preset,
                timestamp: timestamp
            )

            guard !Task.isCancelled else { return }
            previewImage = image
            isPreviewLoading = false
        }
    }

    private func schedulePreviewForTimestampChange(
        for project: RecordingProject,
        refreshPreviewFrame: Bool
    ) {
        guard refreshPreviewFrame || previewVideoURL == nil || previewVideoState != .ready else {
            pendingPreviewTask?.cancel()
            isPreviewLoading = false
            return
        }

        schedulePreview(for: project)
    }

    private func schedulePreviewVideo(
        for project: RecordingProject,
        debounceNanoseconds: UInt64 = 650_000_000,
        showsProgress: Bool = true
    ) {
        pendingPreviewVideoTask?.cancel()

        guard project.sourceVideoURL != nil else {
            previewVideoURL = nil
            previewVideoState = .unavailable
            prefersStaticPreview = false
            return
        }

        previewVideoGeneration += 1
        let generation = previewVideoGeneration
        let preset = exportPreset
        let destinationURL = previewDestinationURL(for: project, generation: generation)
        let hasExistingPreviewVideo = previewVideoURL != nil
        let shouldShowProgress = showsProgress || !hasExistingPreviewVideo
        if shouldShowProgress {
            previewVideoState = hasExistingPreviewVideo ? .updating : .rendering
        }

        pendingPreviewVideoTask = Task { [previewRenderer, projectStore] in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            if shouldShowProgress {
                previewVideoState = hasExistingPreviewVideo ? .updating : .rendering
            }

            do {
                let previewDirectory = projectStore.previewDirectory(for: project)
                try FileManager.default.createDirectory(
                    at: previewDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                let renderedURL = try await previewRenderer.renderPreviewVideo(
                    for: project,
                    preset: preset,
                    destinationURL: destinationURL
                )

                guard !Task.isCancelled, generation == previewVideoGeneration else { return }
                cleanupPreviewVideos(in: previewDirectory, keeping: renderedURL)
                previewVideoURL = renderedURL
                previewVideoState = .ready
                prefersStaticPreview = false
            } catch {
                guard !Task.isCancelled, generation == previewVideoGeneration else { return }
                if shouldShowProgress || previewVideoURL == nil {
                    previewVideoState = .failed(Self.describeExportError(error))
                }
            }
        }
    }

    private func applyTrimChange(start proposedStart: Double?, end proposedEnd: Double?) {
        guard !isApplyingConfiguration, let workingProject = project ?? sourceProject else { return }

        var segments = currentClipSegments
        guard segments.indices.contains(selectedClipSegmentIndex) else { return }

        let segment = segments[selectedClipSegmentIndex]
        let previousEnd = selectedClipSegmentIndex > 0 ? segments[selectedClipSegmentIndex - 1].end : 0
        let nextStartBoundary = selectedClipSegmentIndex < segments.count - 1
            ? segments[selectedClipSegmentIndex + 1].start
            : workingProject.duration
        var nextStart = proposedStart ?? segment.start
        var nextEnd = proposedEnd ?? segment.end

        if workingProject.duration <= minimumTrimDuration {
            nextStart = 0
            nextEnd = workingProject.duration
        } else if let proposedStart {
            nextStart = proposedStart.clamped(to: previousEnd...(segment.end - minimumTrimDuration))
            nextEnd = max(nextEnd, nextStart + minimumTrimDuration).clamped(to: nextStart + minimumTrimDuration...nextStartBoundary)
        } else if let proposedEnd {
            nextEnd = proposedEnd.clamped(to: (segment.start + minimumTrimDuration)...nextStartBoundary)
            nextStart = min(nextStart, nextEnd - minimumTrimDuration).clamped(to: previousEnd...max(nextEnd - minimumTrimDuration, previousEnd))
        }

        guard abs(nextStart - trimStart) > 0.0001 || abs(nextEnd - trimEnd) > 0.0001 else { return }

        segments[selectedClipSegmentIndex] = ProjectTrimRange(start: nextStart, end: nextEnd)
        applyClipSegments(segments, selectedIndex: selectedClipSegmentIndex, workingProject: workingProject)
    }

    private func applyClipSegments(
        _ proposedSegments: [ProjectTrimRange],
        selectedIndex: Int,
        workingProject: RecordingProject
    ) {
        let segments = RecordingProject.normalizedClipSegments(proposedSegments, duration: workingProject.duration)
        let updatedTrimRange = RecordingProject.overallTrimRange(for: segments, duration: workingProject.duration)
        let updatedProject = workingProject.updating(
            style: workingProject.style,
            cameraKeyframes: workingProject.cameraKeyframes,
            trimRange: updatedTrimRange,
            clipSegments: segments
        )

        project = updatedProject
        exportState = .idle
        syncClipState(with: updatedProject.effectiveClipSegments, selectedIndex: selectedIndex)
        previewTimestamp = updatedProject.nearestClipSourceTimestamp(to: previewTimestamp)
        scheduleSave(for: updatedProject)

        if isEditingTimelineTrim {
            pendingPreviewTask?.cancel()
            isPreviewLoading = false
            needsPreviewVideoAfterTrimEdit = true
        } else {
            schedulePreview(for: updatedProject)
        }
    }

    private func updateSelectedManualZoomSegment(_ transform: (ManualZoomSegment) -> ManualZoomSegment) {
        guard let selectedManualZoomSegmentID,
              let workingProject = project ?? sourceProject,
              let index = manualZoomSegments.firstIndex(where: { $0.id == selectedManualZoomSegmentID }) else {
            return
        }

        var segments = manualZoomSegments
        segments[index] = transform(segments[index])
        applyManualZoomSegments(segments, selectedID: selectedManualZoomSegmentID, workingProject: workingProject)
    }

    private func updateManualZoomSegmentTiming(
        id: UUID,
        startClipOffset: TimeInterval,
        endClipOffset: TimeInterval
    ) {
        guard let workingProject = project ?? sourceProject,
              let segment = manualZoomSegments.first(where: { $0.id == id }) else { return }

        let timelineDuration = max(workingProject.trimmedDuration, 0)
        guard timelineDuration > 0 else { return }

        var startOffset = startClipOffset.clamped(to: 0...timelineDuration)
        var endOffset = endClipOffset.clamped(to: 0...timelineDuration)
        if endOffset - startOffset < minimumManualZoomDuration {
            if abs(startOffset - workingProject.clipOffset(forSourceTimestamp: segment.start))
                > abs(endOffset - workingProject.clipOffset(forSourceTimestamp: segment.end)) {
                startOffset = max(0, endOffset - minimumManualZoomDuration)
            } else {
                endOffset = min(timelineDuration, startOffset + minimumManualZoomDuration)
            }
        }

        let sourceStart = workingProject.sourceTimestamp(forClipOffset: startOffset)
        let sourceEnd = workingProject.sourceTimestamp(forClipOffset: endOffset)
        let orderedStart = min(sourceStart, sourceEnd)
        let orderedEnd = max(sourceStart, sourceEnd)

        updateSelectedOrSpecificManualZoomSegment(id: id) { segment in
            segment.updating(
                start: orderedStart,
                end: max(orderedEnd, orderedStart + minimumManualZoomDuration)
            )
        }
    }

    private func updateSelectedOrSpecificManualZoomSegment(
        id: UUID,
        transform: (ManualZoomSegment) -> ManualZoomSegment
    ) {
        guard let workingProject = project ?? sourceProject,
              let index = manualZoomSegments.firstIndex(where: { $0.id == id }) else {
            return
        }

        var segments = manualZoomSegments
        segments[index] = transform(segments[index])
        applyManualZoomSegments(segments, selectedID: id, workingProject: workingProject)
    }

    private func applyManualZoomSegments(
        _ proposedSegments: [ManualZoomSegment],
        selectedID: UUID?,
        workingProject: RecordingProject
    ) {
        let normalizedSegments = RecordingProject.normalizedManualZoomSegments(
            proposedSegments,
            duration: workingProject.duration
        )
        let nextSelectedID = selectedID.flatMap { id in
            normalizedSegments.contains(where: { $0.id == id }) ? id : nil
        }
        let updatedProject = workingProject.updating(
            style: workingProject.style,
            cameraKeyframes: workingProject.cameraKeyframes,
            trimRange: currentTrimRange,
            clipSegments: currentClipSegments,
            manualZoomSegments: normalizedSegments,
            zoomTrackEdited: true
        )

        project = updatedProject
        exportState = .idle
        syncManualZoomState(with: normalizedSegments, selectedID: nextSelectedID)
        previewTimestamp = updatedProject.nearestClipSourceTimestamp(to: previewTimestamp)
        scheduleSave(for: updatedProject)
        schedulePreview(for: updatedProject, debounceNanoseconds: 45_000_000)

        if isEditingManualZoom {
            needsPreviewVideoAfterManualZoomEdit = true
        } else {
            prefersStaticPreview = updatedProject.sourceVideoURL != nil
        }
    }

    private func updatePresenterBubbleStyle(_ transform: (PresenterBubbleStyle) -> PresenterBubbleStyle) {
        guard !isApplyingConfiguration, canEditPresenterBubble, let workingProject = project ?? sourceProject else { return }

        let updatedStyle = transform(workingProject.style.presenterBubbleStyle)
        let projectStyle = ProjectStyle(
            aspectRatio: workingProject.style.aspectRatio,
            backgroundPresetID: workingProject.style.backgroundPresetID,
            cornerRadius: workingProject.style.cornerRadius,
            shadowRadius: workingProject.style.shadowRadius,
            followStrength: workingProject.style.followStrength,
            clickEmphasis: workingProject.style.clickEmphasis,
            padding: workingProject.style.padding,
            presenterBubbleStyle: updatedStyle
        )
        let updatedProject = workingProject.updating(
            style: projectStyle,
            cameraKeyframes: workingProject.cameraKeyframes,
            trimRange: currentTrimRange,
            clipSegments: currentClipSegments
        )

        project = updatedProject
        exportState = .idle
        syncPresenterBubbleState(with: updatedStyle)
        scheduleSave(for: updatedProject)
        schedulePreview(for: updatedProject, debounceNanoseconds: 45_000_000)
        prefersStaticPreview = updatedProject.sourceVideoURL != nil
    }

    private func defaultManualZoomFocus(at timestamp: TimeInterval, in project: RecordingProject) -> NormalizedPoint {
        let sorted = project.events.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return .center }
        if timestamp <= first.timestamp { return first.location }
        guard let last = sorted.last else { return first.location }
        if timestamp >= last.timestamp { return last.location }

        guard let upperIndex = sorted.firstIndex(where: { $0.timestamp >= timestamp }), upperIndex > 0 else {
            return last.location
        }

        let lower = sorted[upperIndex - 1]
        let upper = sorted[upperIndex]
        let span = max(upper.timestamp - lower.timestamp, 0.0001)
        let progress = ((timestamp - lower.timestamp) / span).clamped(to: 0...1)
        return NormalizedPoint(
            x: lower.location.x + ((upper.location.x - lower.location.x) * progress),
            y: lower.location.y + ((upper.location.y - lower.location.y) * progress)
        )
    }

    private func previewDestinationURL(for project: RecordingProject, generation: Int) -> URL {
        let directory = projectStore.previewDirectory(for: project)
        return directory
            .appendingPathComponent("preview-\(generation)", isDirectory: false)
            .appendingPathExtension("mp4")
    }

    private func cleanupPreviewVideos(in directory: URL, keeping keptURL: URL) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls where url.pathExtension.lowercased() == "mp4" && url.standardizedFileURL != keptURL.standardizedFileURL {
            try? fileManager.removeItem(at: url)
        }
    }

    private func defaultPreviewTimestamp(for project: RecordingProject) -> Double {
        project.sourceTimestamp(forClipOffset: 0)
    }

    private var currentTrimRange: ProjectTrimRange {
        RecordingProject.overallTrimRange(for: currentClipSegments, duration: trimUpperBound)
    }

    private var currentClipSegments: [ProjectTrimRange] {
        RecordingProject.normalizedClipSegments(clipSegments, duration: trimUpperBound)
    }

    private func syncClipState(with segments: [ProjectTrimRange], selectedIndex: Int) {
        isApplyingConfiguration = true
        let normalizedSegments = RecordingProject.normalizedClipSegments(segments, duration: trimUpperBound)
        clipSegments = normalizedSegments
        selectedClipSegmentIndex = selectedIndex.clamped(to: 0...max(normalizedSegments.count - 1, 0))
        syncSelectedTrimState()
        isApplyingConfiguration = false
    }

    private func syncManualZoomState(with segments: [ManualZoomSegment], selectedID: UUID?) {
        isApplyingConfiguration = true
        let normalizedSegments = RecordingProject.normalizedManualZoomSegments(segments, duration: trimUpperBound)
        manualZoomSegments = normalizedSegments
        if let selectedID, normalizedSegments.contains(where: { $0.id == selectedID }) {
            selectedManualZoomSegmentID = selectedID
        } else {
            selectedManualZoomSegmentID = nil
        }
        if selectedManualZoomSegmentID == nil {
            isAdjustingManualZoomArea = false
        }
        isApplyingConfiguration = false
    }

    private func syncPresenterBubbleState(with style: PresenterBubbleStyle) {
        isApplyingConfiguration = true
        isPresenterBubbleEnabled = style.isEnabled
        presenterBubblePosition = style.position
        presenterBubbleSize = style.normalizedSize
        presenterBubbleCornerRadiusRatio = style.cornerRadiusRatio
        isApplyingConfiguration = false
    }

    private func syncSelectedTrimState() {
        let segments = currentClipSegments
        guard segments.indices.contains(selectedClipSegmentIndex) else {
            trimStart = 0
            trimEnd = 0
            return
        }

        trimStart = segments[selectedClipSegmentIndex].start
        trimEnd = segments[selectedClipSegmentIndex].end
    }

    private func segmentIndex(containing timestamp: TimeInterval, in segments: [ProjectTrimRange]) -> Int {
        guard !segments.isEmpty else { return 0 }
        if let index = segments.firstIndex(where: { timestamp >= $0.start && timestamp <= $0.end }) {
            return index
        }

        let distances = segments.enumerated().map { index, segment in
            (index, min(abs(timestamp - segment.start), abs(timestamp - segment.end)))
        }
        return distances.min { $0.1 < $1.1 }?.0 ?? 0
    }
}

enum ExportState: Equatable {
    case idle
    case exporting
    case finished(URL)
    case failed(String)
}

enum PreviewVideoState: Equatable {
    case unavailable
    case rendering
    case updating
    case ready
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .rendering, .updating:
            true
        case .unavailable, .ready, .failed:
            false
        }
    }
}
