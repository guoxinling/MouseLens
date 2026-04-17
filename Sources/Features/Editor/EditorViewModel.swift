import AppKit
import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var project: RecordingProject?
    @Published var followStrength = 0.65 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var clickEmphasis = 0.42 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var padding = 0.08 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var cornerRadius = 26.0 {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var selectedBackground: ProjectBackgroundStyle = .aurora {
        didSet { handleStyleChange(updateExportPreset: false) }
    }
    @Published var selectedAspectRatio: ProjectAspectRatio = .landscape {
        didSet { handleStyleChange(updateExportPreset: true) }
    }
    @Published var exportPreset: ExportPreset = .standardLandscape
    @Published var exportState: ExportState = .idle
    @Published var exportURL: URL?
    @Published var showExportSheet = false
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var isPreviewLoading = false
    @Published private(set) var previewTimestamp = 0.0

    private let exportCoordinator: ExportCoordinator
    private let previewRenderer: any ProjectPreviewRendering
    private let cameraPlanEngine: CameraPlanEngine
    private let projectStore: ProjectStore
    private let preferencesStore: AppPreferencesStore
    private let baseZoom = 1.0
    private let clickDuration = 0.6
    private var sourceProject: RecordingProject?
    private var isApplyingConfiguration = false
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingPreviewTask: Task<Void, Never>?

    init(
        exportCoordinator: ExportCoordinator,
        previewRenderer: any ProjectPreviewRendering,
        cameraPlanEngine: CameraPlanEngine,
        projectStore: ProjectStore,
        preferencesStore: AppPreferencesStore
    ) {
        self.exportCoordinator = exportCoordinator
        self.previewRenderer = previewRenderer
        self.cameraPlanEngine = cameraPlanEngine
        self.projectStore = projectStore
        self.preferencesStore = preferencesStore
    }

    deinit {
        pendingSaveTask?.cancel()
        pendingPreviewTask?.cancel()
    }

    func configure(for project: RecordingProject) {
        pendingSaveTask?.cancel()
        pendingPreviewTask?.cancel()
        sourceProject = project
        self.project = project
        isApplyingConfiguration = true
        followStrength = project.style.followStrength
        clickEmphasis = project.style.clickEmphasis
        padding = project.style.padding
        cornerRadius = project.style.cornerRadius
        selectedBackground = project.style.background
        selectedAspectRatio = project.style.aspectRatio
        exportPreset = ExportPreset.defaultPreset(for: project.style.aspectRatio)
        exportState = .idle
        exportURL = nil
        showExportSheet = false
        previewImage = nil
        isPreviewLoading = false
        previewTimestamp = defaultPreviewTimestamp(for: project)
        isApplyingConfiguration = false
        schedulePreview(for: project)
    }

    func export() async {
        guard let project else { return }
        exportState = .exporting
        do {
            let url = try await exportCoordinator.exportVideo(for: project, preset: exportPreset)
            exportURL = url
            exportState = .finished(url)
            if preferencesStore.autoRevealExportInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            showExportSheet = true
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    var previewDuration: Double {
        max(project?.duration ?? sourceProject?.duration ?? 0, 0)
    }

    func updatePreviewTimestamp(_ value: Double) {
        let clamped = value.clamped(to: 0...previewDuration)
        guard abs(clamped - previewTimestamp) > 0.0001 else { return }
        previewTimestamp = clamped

        guard let project else { return }
        schedulePreview(for: project)
    }

    private func handleStyleChange(updateExportPreset: Bool) {
        guard !isApplyingConfiguration, let sourceProject else { return }

        let style = ProjectStyle(
            aspectRatio: selectedAspectRatio,
            background: selectedBackground,
            cornerRadius: cornerRadius,
            shadowRadius: sourceProject.style.shadowRadius,
            followStrength: followStrength,
            clickEmphasis: clickEmphasis,
            padding: padding
        )

        let keyframes = cameraPlanEngine.makePlan(
            from: sourceProject.events,
            baseZoom: baseZoom,
            followStrength: style.followStrength,
            clickRule: ClickEmphasisRule(boost: style.clickEmphasis, duration: clickDuration)
        )
        let duration = max(sourceProject.duration, keyframes.last?.timestamp ?? sourceProject.duration)
        let updatedProject = sourceProject.updating(style: style, cameraKeyframes: keyframes, duration: duration)

        project = updatedProject
        exportState = .idle
        previewTimestamp = previewTimestamp.clamped(to: 0...max(duration, 0))

        if updateExportPreset {
            exportPreset = ExportPreset.defaultPreset(for: style.aspectRatio)
        }

        scheduleSave(for: updatedProject)
        schedulePreview(for: updatedProject)
    }

    private func scheduleSave(for project: RecordingProject) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [projectStore] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            try? projectStore.save(project: project)
        }
    }

    private func schedulePreview(for project: RecordingProject) {
        pendingPreviewTask?.cancel()

        guard project.sourceVideoURL != nil else {
            previewImage = nil
            isPreviewLoading = false
            return
        }

        let timestamp = previewTimestamp.clamped(to: 0...max(project.duration, 0))
        let preset = exportPreset
        isPreviewLoading = true
        previewImage = nil

        pendingPreviewTask = Task { [previewRenderer] in
            try? await Task.sleep(nanoseconds: 120_000_000)
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

    private func defaultPreviewTimestamp(for project: RecordingProject) -> Double {
        guard project.duration > 0 else { return 0 }
        return min(project.duration * 0.25, max(project.duration - 0.1, 0))
    }
}

enum ExportState: Equatable {
    case idle
    case exporting
    case finished(URL)
    case failed(String)
}
