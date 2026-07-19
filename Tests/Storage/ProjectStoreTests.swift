import XCTest
@testable import MouseLens

final class ProjectStoreTests: XCTestCase {
    func testCaptureSessionDurationUsesFirstMediaFrameWhenAvailable() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let mediaStartedAt = startedAt.addingTimeInterval(0.35)
        let endedAt = startedAt.addingTimeInterval(4)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: false, includeSystemAudio: false),
            startedAt: startedAt,
            mediaStartedAt: mediaStartedAt,
            endedAt: endedAt,
            rawCaptureURL: nil,
            coordinateSpace: nil
        )

        XCTAssertEqual(session.duration, 3.65, accuracy: 0.0001)
    }

    func testCreateProjectPersistsMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProjectStore(rootDirectoryURL: directory)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: true, includeSystemAudio: false),
            startedAt: Date(),
            mediaStartedAt: nil,
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
        XCTAssertEqual(savedProject.captureTarget, .screen)
        XCTAssertTrue(savedProject.reconstructsCursor)
        XCTAssertEqual(savedProject.trimRange.start, 0, accuracy: 0.0001)
        XCTAssertEqual(savedProject.trimRange.end, project.duration, accuracy: 0.0001)
        XCTAssertTrue(savedProject.manualZoomSegments.isEmpty)
    }

    func testCreateProjectPreservesPresenterMedia() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let captureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let presenterURL = captureDirectory.appendingPathComponent("presenter.mov")
        let presenterData = Data("mouselens-presenter-media".utf8)
        try presenterData.write(to: presenterURL, options: .atomic)

        let store = ProjectStore(rootDirectoryURL: directory)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: false, includeSystemAudio: false),
            startedAt: Date(timeIntervalSince1970: 100),
            mediaStartedAt: Date(timeIntervalSince1970: 100.2),
            endedAt: Date(timeIntervalSince1970: 104),
            rawCaptureURL: nil,
            coordinateSpace: nil
        )
        let presenterMedia = PresenterMedia(
            sourceVideoURL: presenterURL,
            startedAt: Date(timeIntervalSince1970: 99.9),
            renderOffset: -0.1,
            naturalSize: CGSize(width: 1280, height: 720)
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
            ),
            presenterMedia: presenterMedia
        )

        let savedProject = try XCTUnwrap(try store.loadRecentProjects(limit: 5).first)
        let projectPresenterURL = try XCTUnwrap(project.presenterMedia?.sourceVideoURL)
        XCTAssertTrue(projectPresenterURL.path.contains(project.id.uuidString))
        XCTAssertEqual(projectPresenterURL.lastPathComponent, "presenter.mov")
        XCTAssertEqual(projectPresenterURL, savedProject.presenterMedia?.sourceVideoURL)
        XCTAssertEqual(try Data(contentsOf: projectPresenterURL), presenterData)
        XCTAssertEqual(project.presenterMedia?.startedAt, presenterMedia.startedAt)
        XCTAssertEqual(project.presenterMedia?.renderOffset, presenterMedia.renderOffset)
        XCTAssertEqual(project.presenterMedia?.naturalSize, presenterMedia.naturalSize)
    }

    func testCreateProjectDropsPresenterMediaWhenSourceFileIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingPresenterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let store = ProjectStore(rootDirectoryURL: directory)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: false, includeSystemAudio: false),
            startedAt: Date(timeIntervalSince1970: 100),
            mediaStartedAt: Date(timeIntervalSince1970: 100.2),
            endedAt: Date(timeIntervalSince1970: 104),
            rawCaptureURL: nil,
            coordinateSpace: nil
        )
        let presenterMedia = PresenterMedia(
            sourceVideoURL: missingPresenterURL,
            startedAt: Date(timeIntervalSince1970: 99.9),
            renderOffset: -0.1,
            naturalSize: CGSize(width: 1280, height: 720)
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
                padding: 0.08,
                presenterBubbleStyle: PresenterBubbleStyle(
                    isEnabled: true,
                    position: .bottomRight,
                    normalizedSize: 0.22,
                    shape: .circle,
                    cornerRadius: 18,
                    shadowOpacity: 0.24
                )
            ),
            presenterMedia: presenterMedia
        )

        let savedProject = try XCTUnwrap(try store.loadRecentProjects(limit: 5).first)
        XCTAssertNil(project.presenterMedia)
        XCTAssertNil(savedProject.presenterMedia)
    }

    func testProjectStylePersistsPresenterBubbleStyle() throws {
        let style = ProjectStyle(
            aspectRatio: .landscape,
            backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
            cornerRadius: 10.35,
            shadowRadius: 24,
            followStrength: 0.72,
            clickEmphasis: 0.54,
            padding: 0.04,
            presenterBubbleStyle: PresenterBubbleStyle(
                isEnabled: true,
                position: .bottomRight,
                normalizedSize: 0.22,
                shape: .circle,
                cornerRadius: 18,
                shadowOpacity: 0.24
            )
        )

        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(ProjectStyle.self, from: encoded)

        XCTAssertEqual(decoded.presenterBubbleStyle, style.presenterBubbleStyle)
    }

    func testPresenterBubbleStyleDecodesLegacyBottomRightCircleIntoFreePosition() throws {
        let legacyJSON = """
        {
          "isEnabled": true,
          "position": "bottomRight",
          "normalizedSize": 0.22,
          "shape": "circle",
          "cornerRadius": 18,
          "shadowOpacity": 0.24
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PresenterBubbleStyle.self, from: legacyJSON)

        XCTAssertEqual(decoded.normalizedCenter.x, 1, accuracy: 0.0001)
        XCTAssertEqual(decoded.normalizedCenter.y, 1, accuracy: 0.0001)
        XCTAssertEqual(decoded.cornerRadiusRatio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.source, .camera)
    }

    func testPresenterBubbleStylePersistsReservedPresenterSource() throws {
        let style = PresenterBubbleStyle(
            isEnabled: true,
            normalizedCenter: NormalizedPoint(x: 0.38, y: 0.72),
            normalizedSize: 0.24,
            cornerRadiusRatio: 0.18,
            shadowOpacity: 0.31,
            source: .avatarImage
        )

        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(PresenterBubbleStyle.self, from: encoded)

        XCTAssertEqual(decoded, style)
        XCTAssertEqual(decoded.source, .avatarImage)
    }

    func testLegacyProjectStyleWithoutPresenterBubbleStyleUsesDefault() throws {
        let style = ProjectStyle(
            aspectRatio: .landscape,
            backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
            cornerRadius: 10.35,
            shadowRadius: 24,
            followStrength: 0.72,
            clickEmphasis: 0.54,
            padding: 0.04
        )

        let encoded = try JSONEncoder().encode(style)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "presenterBubbleStyle")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.prettyPrinted, .sortedKeys])
        let decoded = try JSONDecoder().decode(ProjectStyle.self, from: legacyData)

        XCTAssertEqual(decoded.presenterBubbleStyle, .defaultValue)
    }

    func testRecordingProjectPersistsPresenterMedia() throws {
        let media = PresenterMedia(
            sourceVideoURL: URL(fileURLWithPath: "/tmp/presenter.mov"),
            startedAt: Date(timeIntervalSince1970: 10),
            renderOffset: 0.12,
            naturalSize: CGSize(width: 1280, height: 720)
        )

        let project = RecordingProject(
            id: UUID(),
            name: "Demo",
            createdAt: Date(timeIntervalSince1970: 20),
            duration: 6,
            sourceVideoURL: URL(fileURLWithPath: "/tmp/source.mov"),
            captureTarget: .screen,
            reconstructsCursor: true,
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1)],
            style: ProjectStyle(
                aspectRatio: .landscape,
                backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
                cornerRadius: 10.35,
                shadowRadius: 24,
                followStrength: 0.72,
                clickEmphasis: 0.54,
                padding: 0.04
            ),
            presenterMedia: media
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(RecordingProject.self, from: encoded)

        XCTAssertEqual(decoded.presenterMedia, media)
    }

    func testLegacyRecordingProjectWithoutPresenterMediaDefaultsToNil() throws {
        let project = RecordingProject(
            id: UUID(),
            name: "LegacyNoPresenterMedia",
            createdAt: Date(timeIntervalSince1970: 20),
            duration: 6,
            sourceVideoURL: URL(fileURLWithPath: "/tmp/source.mov"),
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1)],
            style: ProjectStyle(
                aspectRatio: .landscape,
                backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
                cornerRadius: 10.35,
                shadowRadius: 24,
                followStrength: 0.72,
                clickEmphasis: 0.54,
                padding: 0.04
            )
        )

        let encoded = try JSONEncoder().encode(project)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "presenterMedia")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.prettyPrinted, .sortedKeys])
        let decoded = try JSONDecoder().decode(RecordingProject.self, from: legacyData)

        XCTAssertNil(decoded.presenterMedia)
    }

    func testCreateProjectWritesCoordinateDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProjectStore(rootDirectoryURL: directory)
        let rawClick = PointerEvent(
            timestamp: 0.2,
            location: NormalizedPoint(x: 0.9, y: 0.9),
            globalLocation: PointerGlobalLocation(x: 300, y: 600),
            type: .click
        )
        let normalizedClick = PointerEvent(
            id: rawClick.id,
            timestamp: 0.2,
            location: NormalizedPoint(x: 0.4, y: 0.3),
            globalLocation: rawClick.globalLocation,
            type: .click
        )
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .screen, includeMicrophone: false, includeSystemAudio: false),
            startedAt: Date(),
            mediaStartedAt: nil,
            endedAt: Date().addingTimeInterval(3),
            rawCaptureURL: nil,
            coordinateSpace: nil
        )

        let project = try store.createProject(
            from: session,
            rawEvents: [rawClick],
            events: [normalizedClick],
            keyframes: [
                CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
                CameraKeyframe(timestamp: 0.7, focus: NormalizedPoint(x: 0.4, y: 0.3), zoom: 1.7)
            ],
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

        let data = try Data(contentsOf: store.coordinateDiagnosticsURL(for: project))
        let diagnostics = try JSONDecoder().decode(CoordinateDiagnostics.self, from: data)

        XCTAssertEqual(diagnostics.rawClickCount, 1)
        XCTAssertEqual(diagnostics.normalizedClickCount, 1)
        XCTAssertEqual(diagnostics.pointerTimelineOffset, 0, accuracy: 0.0001)
        XCTAssertTrue(diagnostics.droppedClicks.isEmpty)
        let alignment = try XCTUnwrap(diagnostics.clickAlignments.first)
        XCTAssertEqual(alignment.clickLocation.x, 0.4, accuracy: 0.0001)
    }

    func testCreateProjectPersistsWindowCaptureTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProjectStore(rootDirectoryURL: directory)
        let session = CaptureSession(
            id: UUID(),
            configuration: .init(target: .window, includeMicrophone: false, includeSystemAudio: false),
            startedAt: Date(),
            mediaStartedAt: nil,
            endedAt: Date().addingTimeInterval(3),
            rawCaptureURL: nil,
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

        XCTAssertEqual(project.captureTarget, .window)
        XCTAssertEqual(try store.loadRecentProjects(limit: 1).first?.captureTarget, .window)
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
            events: [
                PointerEvent(timestamp: 1.0, location: .init(x: 0.2, y: 0.3), type: .click)
            ],
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
        XCTAssertGreaterThan(segment.zoomLevel, 1.25)
        XCTAssertEqual(segment.focus.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(segment.focus.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(segment.easeInDuration, 0.08, accuracy: 0.0001)
        XCTAssertEqual(segment.easeOutDuration, 0, accuracy: 0.0001)
    }

    func testAutoZoomSegmentsFollowEachClickInsteadOfReusingPeakFrameFocus() throws {
        let project = RecordingProject(
            id: UUID(),
            name: "ClickAnchoredAutoZoomTrack",
            createdAt: Date(timeIntervalSince1970: 1_776_368_400),
            duration: 8,
            sourceVideoURL: nil,
            events: [
                PointerEvent(timestamp: 1.0, location: .init(x: 0.12, y: 0.18), type: .click),
                PointerEvent(timestamp: 3.0, location: .init(x: 0.82, y: 0.20), type: .click),
                PointerEvent(timestamp: 4.2, location: .init(x: 0.52, y: 0.52), type: .click)
            ],
            cameraKeyframes: [
                CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
                CameraKeyframe(timestamp: 1.5, focus: .init(x: 0.12, y: 0.18), zoom: 1.45),
                CameraKeyframe(timestamp: 3.5, focus: .init(x: 0.82, y: 0.20), zoom: 1.6),
                CameraKeyframe(timestamp: 4.7, focus: .init(x: 0.52, y: 0.52), zoom: 1.5),
                CameraKeyframe(timestamp: 7, focus: .center, zoom: 1.0)
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

        XCTAssertEqual(project.manualZoomSegments.count, 3)
        XCTAssertEqual(project.manualZoomSegments[0].focus.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(project.manualZoomSegments[0].focus.y, 0.18, accuracy: 0.0001)
        XCTAssertEqual(project.manualZoomSegments[1].focus.x, 0.82, accuracy: 0.0001)
        XCTAssertEqual(project.manualZoomSegments[1].focus.y, 0.20, accuracy: 0.0001)
        XCTAssertEqual(project.manualZoomSegments[2].focus.x, 0.52, accuracy: 0.0001)
        XCTAssertEqual(project.manualZoomSegments[2].focus.y, 0.52, accuracy: 0.0001)
        XCTAssertTrue(project.manualZoomSegments.allSatisfy { $0.easeInDuration == 0.08 })
        XCTAssertTrue(project.manualZoomSegments.allSatisfy { $0.easeOutDuration == 0 })
        XCTAssertLessThanOrEqual(project.manualZoomSegments[0].end, project.manualZoomSegments[1].start + 0.0001)
        XCTAssertLessThanOrEqual(project.manualZoomSegments[1].end, project.manualZoomSegments[2].start + 0.0001)
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
            mediaStartedAt: nil,
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
