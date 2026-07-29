import XCTest
@testable import MouseLens

final class ExportFilenameTests: XCTestCase {
    func testExportFormatUsesMatchingFileExtension() {
        XCTAssertEqual(ExportFormat.mp4.fileExtension, "mp4")
        XCTAssertEqual(ExportFormat.gif.fileExtension, "gif")
    }

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

        XCTAssertTrue(filename.hasPrefix("MouseLens_"))
        XCTAssertTrue(filename.hasSuffix("-standardLandscape.mp4"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(" "))
    }

    func testConfiguredMP4ExportFilenameUsesReadableResolutionFrameRateAndDate() {
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
            resolution: .p2160,
            frameRate: .fps60,
            quality: .small,
            includesCursor: false,
            includesClickFeedback: false
        )

        let filename = ExportCoordinator.exportFilename(
            for: project,
            configuration: configuration
        )

        XCTAssertEqual(configuration.renderSize(for: .portrait), CGSize(width: 2160, height: 3840))
        XCTAssertTrue(filename.hasPrefix("MouseLens_4K_60fps_"))
        XCTAssertTrue(filename.hasSuffix(".mp4"))
        XCTAssertFalse(filename.contains("p2160"))
        XCTAssertFalse(filename.contains(" "))
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
            ExportCoordinator.exportFilename(for: project, configuration: configuration).contains("MouseLens_GIF_1080p_15fps_")
        )
        XCTAssertTrue(
            ExportCoordinator.exportFilename(for: project, configuration: configuration).hasSuffix(".gif")
        )
    }
}
