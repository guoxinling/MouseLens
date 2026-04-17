import Foundation

enum ProjectAspectRatio: String, CaseIterable, Codable {
    case landscape
    case portrait
    case square

    var label: String {
        switch self {
        case .landscape: "16:9"
        case .portrait: "9:16"
        case .square: "1:1"
        }
    }
}

enum ProjectBackgroundStyle: String, Codable, CaseIterable {
    case aurora
    case graphite
    case sunrise

    var label: String {
        switch self {
        case .aurora: "Aurora"
        case .graphite: "Graphite"
        case .sunrise: "Sunrise"
        }
    }
}

struct ProjectStyle: Codable, Equatable {
    let aspectRatio: ProjectAspectRatio
    let background: ProjectBackgroundStyle
    let cornerRadius: Double
    let shadowRadius: Double
    let followStrength: Double
    let clickEmphasis: Double
    let padding: Double
}

struct RecordingProject: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let duration: TimeInterval
    let sourceVideoURL: URL?
    let events: [PointerEvent]
    let cameraKeyframes: [CameraKeyframe]
    let style: ProjectStyle

    func updating(style: ProjectStyle, cameraKeyframes: [CameraKeyframe], duration: TimeInterval? = nil) -> RecordingProject {
        RecordingProject(
            id: id,
            name: name,
            createdAt: createdAt,
            duration: duration ?? self.duration,
            sourceVideoURL: sourceVideoURL,
            events: events,
            cameraKeyframes: cameraKeyframes,
            style: style
        )
    }
}

struct FileLayout {
    let root: URL
    let metadataURL: URL
    let exportDirectoryURL: URL
}

final class ProjectStore {
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootDirectoryURL: URL? = nil) {
        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.rootDirectoryURL = support.appendingPathComponent("MouseLens", isDirectory: true)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func createProject(
        from session: CaptureSession,
        events: [PointerEvent],
        keyframes: [CameraKeyframe],
        style: ProjectStyle
    ) throws -> RecordingProject {
        let createdAt = Date()
        let slug = createdAt.formatted(.dateTime.year().month().day().hour().minute())
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")

        let project = RecordingProject(
            id: session.id,
            name: "Demo_\(slug)",
            createdAt: createdAt,
            duration: max(session.duration, keyframes.last?.timestamp ?? 6),
            sourceVideoURL: session.rawCaptureURL,
            events: events,
            cameraKeyframes: keyframes,
            style: style
        )

        try save(project: project)
        return project
    }

    func save(project: RecordingProject) throws {
        let layout = layout(for: project.id)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: layout.exportDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(project)
        try data.write(to: layout.metadataURL, options: .atomic)
    }

    func loadRecentProjects(limit: Int) throws -> [RecordingProject] {
        guard FileManager.default.fileExists(atPath: rootDirectoryURL.path) else {
            return []
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let projects = try directories.compactMap { directory -> RecordingProject? in
            let metadataURL = directory.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }
            let data = try Data(contentsOf: metadataURL)
            return try decoder.decode(RecordingProject.self, from: data)
        }

        return Array(projects.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func exportDirectory(for project: RecordingProject) -> URL {
        layout(for: project.id).exportDirectoryURL
    }

    private func layout(for id: UUID) -> FileLayout {
        let root = rootDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        return FileLayout(
            root: root,
            metadataURL: root.appendingPathComponent("project.json"),
            exportDirectoryURL: root.appendingPathComponent("Exports", isDirectory: true)
        )
    }
}
