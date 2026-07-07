import XCTest
@testable import MouseLens

final class ExportFilenameTests: XCTestCase {
    func testExportFilenameSanitizesProjectName() {
        let project = RecordingProject(
            id: UUID(),
            name: "Demo: Apr 17 / Product Tour",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 10,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0)],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.7,
                clickEmphasis: 0.5,
                padding: 0.08
            )
        )

        let filename = ExportCoordinator.exportFilename(for: project, preset: .standardLandscape)

        XCTAssertTrue(filename.hasPrefix("Demo_Apr_17_Product_Tour-"))
        XCTAssertTrue(filename.hasSuffix("-standardLandscape.mp4"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(" "))
    }

    func testConfiguredExportFilenameUsesFormatAndResolution() {
        let project = RecordingProject(
            id: UUID(),
            name: "Product Tour",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 10,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0)],
            style: ProjectStyle(
                aspectRatio: .portrait,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.7,
                clickEmphasis: 0.5,
                padding: 0.08
            )
        )
        let configuration = ExportConfiguration(
            format: .mp4,
            resolution: .p720,
            frameRate: .fps15,
            quality: .small,
            includesCursor: false,
            includesClickFeedback: false
        )

        let filename = ExportCoordinator.exportFilename(
            for: project,
            configuration: configuration
        )

        XCTAssertEqual(configuration.renderSize(for: .portrait), CGSize(width: 720, height: 1280))
        XCTAssertTrue(filename.hasSuffix("-mp4-p720.mp4"))
    }

    func testGIFExportFilenameUsesGIFExtension() {
        let project = RecordingProject(
            id: UUID(),
            name: "Product Tour",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 10,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0)],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.7,
                clickEmphasis: 0.5,
                padding: 0.08
            )
        )
        let configuration = ExportConfiguration.recommended(for: .landscape, format: .gif)

        XCTAssertTrue(
            ExportCoordinator.exportFilename(for: project, configuration: configuration).hasSuffix("-gif-p720.gif")
        )
    }
}
