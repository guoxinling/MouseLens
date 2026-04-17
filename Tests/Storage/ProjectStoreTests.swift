import XCTest
@testable import MouseLens

final class ProjectStoreTests: XCTestCase {
    func testCreateProjectPersistsMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProjectStore(rootDirectoryURL: directory)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: true, includeSystemAudio: false),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(3),
            rawCaptureURL: nil,
            coordinateSpace: nil
        )

        let project = try store.createProject(
            from: session,
            events: [PointerEvent(timestamp: 0, location: .center, type: .move)],
            keyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0)],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 24,
                shadowRadius: 16,
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            )
        )

        let recents = try store.loadRecentProjects(limit: 5)
        XCTAssertEqual(recents.first?.id, project.id)
        XCTAssertEqual(recents.first?.style.aspectRatio, .landscape)
    }
}
