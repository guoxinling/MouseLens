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
        let savedProject = try XCTUnwrap(recents.first)
        XCTAssertEqual(savedProject.id, project.id)
        XCTAssertEqual(savedProject.style.aspectRatio, .landscape)
        XCTAssertTrue(savedProject.reconstructsCursor)
        XCTAssertEqual(savedProject.trimRange.start, 0, accuracy: 0.0001)
        XCTAssertEqual(savedProject.trimRange.end, project.duration, accuracy: 0.0001)
        XCTAssertTrue(savedProject.manualZoomSegments.isEmpty)
    }

    func testLegacyProjectWithoutTrimRangeDefaultsToFullDuration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectID = UUID()
        let projectDirectory = directory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        let project = RecordingProject(
            id: projectID,
            name: "LegacyProject",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 12,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0)],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            )
        )

        let encoded = try JSONEncoder().encode(project)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "trimRange")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.prettyPrinted, .sortedKeys])
        let metadataURL = projectDirectory.appendingPathComponent("project.json")
        try legacyData.write(to: metadataURL, options: .atomic)

        let store = ProjectStore(rootDirectoryURL: directory)
        let recents = try store.loadRecentProjects(limit: 5)

        let savedProject = try XCTUnwrap(recents.first)
        XCTAssertEqual(savedProject.id, projectID)
        XCTAssertFalse(savedProject.reconstructsCursor)
        XCTAssertEqual(savedProject.trimRange.start, 0, accuracy: 0.0001)
        XCTAssertEqual(savedProject.trimRange.end, 12, accuracy: 0.0001)
    }

    func testLegacyProjectWithoutClipSegmentsUsesTrimRangeAsSingleSegment() throws {
        let project = RecordingProject(
            id: UUID(),
            name: "LegacyTrimOnly",
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
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            ),
            trimRange: ProjectTrimRange(start: 2, end: 8)
        )

        let encoded = try JSONEncoder().encode(project)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "clipSegments")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.prettyPrinted, .sortedKeys])
        let savedProject = try JSONDecoder().decode(RecordingProject.self, from: legacyData)

        XCTAssertEqual(savedProject.effectiveClipSegments, [ProjectTrimRange(start: 2, end: 8)])
        XCTAssertEqual(savedProject.trimmedDuration, 6, accuracy: 0.0001)
        XCTAssertTrue(savedProject.manualZoomSegments.isEmpty)
    }

    func testLegacyProjectWithoutManualZoomSegmentsDefaultsToEmptyList() throws {
        let project = RecordingProject(
            id: UUID(),
            name: "LegacyNoManualZoom",
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
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            ),
            manualZoomSegments: [
                ManualZoomSegment(start: 1, end: 3, focus: .init(x: 0.8, y: 0.2), zoomLevel: 2.0)
            ]
        )

        let encoded = try JSONEncoder().encode(project)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "manualZoomSegments")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.prettyPrinted, .sortedKeys])
        let savedProject = try JSONDecoder().decode(RecordingProject.self, from: legacyData)

        XCTAssertTrue(savedProject.manualZoomSegments.isEmpty)
    }

    func testLegacyManualZoomSegmentDefaultsToManualSource() throws {
        let project = RecordingProject(
            id: UUID(),
            name: "LegacyManualZoomSource",
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
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            ),
            manualZoomSegments: [
                ManualZoomSegment(start: 1, end: 3, focus: .init(x: 0.8, y: 0.2), zoomLevel: 2.0)
            ],
            zoomTrackEdited: true
        )

        let encoded = try JSONEncoder().encode(project)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var segments = try XCTUnwrap(legacyObject["manualZoomSegments"] as? [[String: Any]])
        segments[0].removeValue(forKey: "source")
        legacyObject["manualZoomSegments"] = segments

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.prettyPrinted, .sortedKeys])
        let savedProject = try JSONDecoder().decode(RecordingProject.self, from: legacyData)

        XCTAssertEqual(savedProject.manualZoomSegments.first?.source, .manual)
    }

    func testProjectGeneratesAutoZoomSegmentsWhenTrackIsNotEdited() throws {
        let project = RecordingProject(
            id: UUID(),
            name: "AutoZoomTrack",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 4,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [
                CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
                CameraKeyframe(timestamp: 1.0, focus: .init(x: 0.2, y: 0.3), zoom: 1.55),
                CameraKeyframe(timestamp: 1.6, focus: .init(x: 0.25, y: 0.35), zoom: 1.7),
                CameraKeyframe(timestamp: 2.2, focus: .center, zoom: 1.0)
            ],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            )
        )

        let segment = try XCTUnwrap(project.manualZoomSegments.first)
        XCTAssertEqual(project.manualZoomSegments.count, 1)
        XCTAssertEqual(segment.source, .auto)
        XCTAssertEqual(segment.zoomLevel, 1.7, accuracy: 0.0001)
        XCTAssertEqual(segment.focus.x, 0.25, accuracy: 0.0001)
    }

    func testEditedZoomTrackCanStayEmpty() {
        let project = RecordingProject(
            id: UUID(),
            name: "EditedEmptyZoomTrack",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 4,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [
                CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
                CameraKeyframe(timestamp: 1.0, focus: .init(x: 0.2, y: 0.3), zoom: 1.55)
            ],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            ),
            manualZoomSegments: [],
            zoomTrackEdited: true
        )

        XCTAssertTrue(project.manualZoomSegments.isEmpty)
    }

    func testManualZoomSegmentsCutOverlappingAutoSegments() throws {
        let auto = ManualZoomSegment(
            start: 1.0,
            end: 5.0,
            focus: .center,
            zoomLevel: 1.6,
            source: .auto
        )
        let manual = ManualZoomSegment(
            start: 2.0,
            end: 3.0,
            focus: .init(x: 0.8, y: 0.2),
            zoomLevel: 2.1,
            source: .manual
        )

        let normalized = RecordingProject.normalizedManualZoomSegments([auto, manual], duration: 6)

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0].source, .auto)
        XCTAssertEqual(normalized[0].start, 1.0, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].end, 2.0, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].source, .manual)
        XCTAssertEqual(normalized[1].start, 2.0, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].end, 3.0, accuracy: 0.0001)
        XCTAssertEqual(normalized[2].source, .auto)
        XCTAssertEqual(normalized[2].start, 3.0, accuracy: 0.0001)
        XCTAssertEqual(normalized[2].end, 5.0, accuracy: 0.0001)
        XCTAssertEqual(Set(normalized.map(\.id)).count, 3)
    }

    func testClipSegmentsMapBetweenClipAndSourceTimelines() {
        let project = RecordingProject(
            id: UUID(),
            name: "CutListProject",
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
                followStrength: 0.5,
                clickEmphasis: 0.4,
                padding: 0.08
            ),
            clipSegments: [
                ProjectTrimRange(start: 1, end: 3),
                ProjectTrimRange(start: 7, end: 9)
            ]
        )

        XCTAssertEqual(project.trimmedDuration, 4, accuracy: 0.0001)
        XCTAssertEqual(project.sourceTimestamp(forClipOffset: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(project.sourceTimestamp(forClipOffset: 1.5), 2.5, accuracy: 0.0001)
        XCTAssertEqual(project.sourceTimestamp(forClipOffset: 2.5), 7.5, accuracy: 0.0001)
        XCTAssertEqual(project.clipOffset(forSourceTimestamp: 7.5), 2.5, accuracy: 0.0001)
        XCTAssertEqual(project.nearestClipSourceTimestamp(to: 5), 3, accuracy: 0.0001)
    }

    func testCreateProjectCopiesRawCaptureIntoProjectDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let captureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        let rawCaptureURL = captureDirectory.appendingPathComponent("capture.mov")
        let captureData = Data("mouselens-test-capture".utf8)
        try captureData.write(to: rawCaptureURL, options: .atomic)

        let store = ProjectStore(rootDirectoryURL: directory)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: false, includeSystemAudio: false),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(5),
            rawCaptureURL: rawCaptureURL,
            coordinateSpace: nil
        )

        let project = try store.createProject(
            from: session,
            events: [],
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

        let savedSourceURL = try XCTUnwrap(project.sourceVideoURL)
        XCTAssertTrue(savedSourceURL.path.contains(project.id.uuidString))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedSourceURL.path))
        XCTAssertEqual(try Data(contentsOf: savedSourceURL), captureData)
        XCTAssertTrue(project.reconstructsCursor)
    }
}
