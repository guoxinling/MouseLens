import XCTest
@testable import MouseLens

@MainActor
final class EditorViewModelTests: XCTestCase {
    func testChangingFollowStrengthRebuildsDraftProject() {
        let viewModel = makeViewModel()
        let project = makeProject(followStrength: 0.65, aspectRatio: .landscape)

        viewModel.configure(for: project)
        let originalFocusX = viewModel.project?.cameraKeyframes.last?.focus.x

        viewModel.followStrength = 0.2

        XCTAssertEqual(viewModel.project?.style.followStrength ?? -1, 0.2, accuracy: 0.0001)
        XCTAssertNotEqual(viewModel.project?.cameraKeyframes.last?.focus.x, originalFocusX)
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

    private func makeProject(followStrength: Double, aspectRatio: ProjectAspectRatio) -> RecordingProject {
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
            )
        )
    }
}
