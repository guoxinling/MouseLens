import AVFoundation
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
    case ocean
    case plum
    case moss
    case paper
    case midnight

    var label: String {
        switch self {
        case .aurora: "Aurora"
        case .graphite: "Graphite"
        case .sunrise: "Sunrise"
        case .ocean: "Ocean"
        case .plum: "Plum"
        case .moss: "Moss"
        case .paper: "Paper"
        case .midnight: "Midnight"
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

struct ProjectTrimRange: Codable, Equatable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        max(end - start, 0)
    }

    func clamped(to duration: TimeInterval) -> ProjectTrimRange {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else {
            return ProjectTrimRange(start: 0, end: 0)
        }

        let clampedStart = start.clamped(to: 0...safeDuration)
        let clampedEnd = end.clamped(to: clampedStart...safeDuration)
        return ProjectTrimRange(start: clampedStart, end: clampedEnd)
    }
}

enum ZoomSegmentSource: String, Codable {
    case auto
    case manual
}

struct ManualZoomSegment: Identifiable, Codable, Equatable {
    static let minimumDuration: TimeInterval = 0.2
    static let defaultDuration: TimeInterval = 2.2
    static let defaultZoomLevel = 1.7
    static let defaultEaseDuration: TimeInterval = 0.35
    static let zoomRange: ClosedRange<Double> = 1.0...2.4

    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let focus: NormalizedPoint
    let zoomLevel: Double
    let easeInDuration: TimeInterval
    let easeOutDuration: TimeInterval
    let source: ZoomSegmentSource

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        focus: NormalizedPoint,
        zoomLevel: Double = ManualZoomSegment.defaultZoomLevel,
        easeInDuration: TimeInterval = ManualZoomSegment.defaultEaseDuration,
        easeOutDuration: TimeInterval = ManualZoomSegment.defaultEaseDuration,
        source: ZoomSegmentSource = .manual
    ) {
        self.id = id
        self.start = max(start, 0)
        self.end = max(end, start)
        self.focus = NormalizedPoint(
            x: focus.x.clamped(to: 0...1),
            y: focus.y.clamped(to: 0...1)
        )
        self.zoomLevel = zoomLevel.clamped(to: Self.zoomRange)
        self.easeInDuration = max(easeInDuration, 0)
        self.easeOutDuration = max(easeOutDuration, 0)
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case focus
        case zoomLevel
        case easeInDuration
        case easeOutDuration
        case source
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            start: try container.decode(TimeInterval.self, forKey: .start),
            end: try container.decode(TimeInterval.self, forKey: .end),
            focus: try container.decode(NormalizedPoint.self, forKey: .focus),
            zoomLevel: try container.decode(Double.self, forKey: .zoomLevel),
            easeInDuration: try container.decode(TimeInterval.self, forKey: .easeInDuration),
            easeOutDuration: try container.decode(TimeInterval.self, forKey: .easeOutDuration),
            source: try container.decodeIfPresent(ZoomSegmentSource.self, forKey: .source) ?? .manual
        )
    }

    var duration: TimeInterval {
        max(end - start, 0)
    }

    func clamped(to duration: TimeInterval) -> ManualZoomSegment {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else {
            return ManualZoomSegment(
                id: id,
                start: 0,
                end: 0,
                focus: focus,
                zoomLevel: zoomLevel,
                easeInDuration: easeInDuration,
                easeOutDuration: easeOutDuration,
                source: source
            )
        }

        let clampedStart = start.clamped(to: 0...safeDuration)
        let clampedEnd = end.clamped(to: clampedStart...safeDuration)
        return ManualZoomSegment(
            id: id,
            start: clampedStart,
            end: clampedEnd,
            focus: focus,
            zoomLevel: zoomLevel,
            easeInDuration: min(easeInDuration, max(clampedEnd - clampedStart, 0) / 2),
            easeOutDuration: min(easeOutDuration, max(clampedEnd - clampedStart, 0) / 2),
            source: source
        )
    }

    func updating(
        start: TimeInterval? = nil,
        end: TimeInterval? = nil,
        focus: NormalizedPoint? = nil,
        zoomLevel: Double? = nil,
        easeInDuration: TimeInterval? = nil,
        easeOutDuration: TimeInterval? = nil,
        source: ZoomSegmentSource? = nil
    ) -> ManualZoomSegment {
        ManualZoomSegment(
            id: id,
            start: start ?? self.start,
            end: end ?? self.end,
            focus: focus ?? self.focus,
            zoomLevel: zoomLevel ?? self.zoomLevel,
            easeInDuration: easeInDuration ?? self.easeInDuration,
            easeOutDuration: easeOutDuration ?? self.easeOutDuration,
            source: source ?? self.source
        )
    }
}

struct RecordingProject: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let duration: TimeInterval
    let sourceVideoURL: URL?
    let reconstructsCursor: Bool
    let events: [PointerEvent]
    let cameraKeyframes: [CameraKeyframe]
    let style: ProjectStyle
    let trimRange: ProjectTrimRange
    let clipSegments: [ProjectTrimRange]
    let manualZoomSegments: [ManualZoomSegment]
    let zoomTrackEdited: Bool

    var effectiveTrimRange: ProjectTrimRange {
        trimRange.clamped(to: duration)
    }

    var effectiveClipSegments: [ProjectTrimRange] {
        Self.normalizedClipSegments(
            clipSegments.isEmpty ? [effectiveTrimRange] : clipSegments,
            duration: duration
        )
    }

    var trimmedDuration: TimeInterval {
        effectiveClipSegments.reduce(0) { $0 + $1.duration }
    }

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        duration: TimeInterval,
        sourceVideoURL: URL?,
        reconstructsCursor: Bool = false,
        events: [PointerEvent],
        cameraKeyframes: [CameraKeyframe],
        style: ProjectStyle,
        trimRange: ProjectTrimRange? = nil,
        clipSegments: [ProjectTrimRange]? = nil,
        manualZoomSegments: [ManualZoomSegment] = [],
        zoomTrackEdited: Bool = false
    ) {
        let safeDuration = max(duration, 0)
        let safeTrimRange = (trimRange ?? ProjectTrimRange(start: 0, end: safeDuration)).clamped(to: safeDuration)
        let proposedZoomSegments = manualZoomSegments.isEmpty && zoomTrackEdited == false
            ? Self.autoZoomSegments(from: cameraKeyframes, duration: safeDuration)
            : manualZoomSegments
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = safeDuration
        self.sourceVideoURL = sourceVideoURL
        self.reconstructsCursor = reconstructsCursor
        self.events = events
        self.cameraKeyframes = cameraKeyframes
        self.style = style
        self.trimRange = safeTrimRange
        self.clipSegments = Self.normalizedClipSegments(clipSegments ?? [safeTrimRange], duration: safeDuration)
        self.manualZoomSegments = Self.normalizedManualZoomSegments(proposedZoomSegments, duration: safeDuration)
        self.zoomTrackEdited = zoomTrackEdited
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case duration
        case sourceVideoURL
        case reconstructsCursor
        case events
        case cameraKeyframes
        case style
        case trimRange
        case clipSegments
        case manualZoomSegments
        case zoomTrackEdited
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let duration = try container.decode(TimeInterval.self, forKey: .duration)
        let sourceVideoURL = try container.decodeIfPresent(URL.self, forKey: .sourceVideoURL)
        let reconstructsCursor = try container.decodeIfPresent(Bool.self, forKey: .reconstructsCursor) ?? false
        let events = try container.decode([PointerEvent].self, forKey: .events)
        let cameraKeyframes = try container.decode([CameraKeyframe].self, forKey: .cameraKeyframes)
        let style = try container.decode(ProjectStyle.self, forKey: .style)
        let trimRange = try container.decodeIfPresent(ProjectTrimRange.self, forKey: .trimRange)
        let clipSegments = try container.decodeIfPresent([ProjectTrimRange].self, forKey: .clipSegments)
        let manualZoomSegments = try container.decodeIfPresent([ManualZoomSegment].self, forKey: .manualZoomSegments) ?? []
        let zoomTrackEdited = try container.decodeIfPresent(Bool.self, forKey: .zoomTrackEdited) ?? false

        self.init(
            id: id,
            name: name,
            createdAt: createdAt,
            duration: duration,
            sourceVideoURL: sourceVideoURL,
            reconstructsCursor: reconstructsCursor,
            events: events,
            cameraKeyframes: cameraKeyframes,
            style: style,
            trimRange: trimRange,
            clipSegments: clipSegments,
            manualZoomSegments: manualZoomSegments,
            zoomTrackEdited: zoomTrackEdited
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(sourceVideoURL, forKey: .sourceVideoURL)
        try container.encode(reconstructsCursor, forKey: .reconstructsCursor)
        try container.encode(events, forKey: .events)
        try container.encode(cameraKeyframes, forKey: .cameraKeyframes)
        try container.encode(style, forKey: .style)
        try container.encode(trimRange, forKey: .trimRange)
        try container.encode(clipSegments, forKey: .clipSegments)
        try container.encode(manualZoomSegments, forKey: .manualZoomSegments)
        try container.encode(zoomTrackEdited, forKey: .zoomTrackEdited)
    }

    func updating(
        style: ProjectStyle,
        cameraKeyframes: [CameraKeyframe],
        duration: TimeInterval? = nil,
        trimRange: ProjectTrimRange? = nil,
        clipSegments: [ProjectTrimRange]? = nil,
        manualZoomSegments: [ManualZoomSegment]? = nil,
        zoomTrackEdited: Bool? = nil
    ) -> RecordingProject {
        let nextDuration = duration ?? self.duration
        let nextSegments = clipSegments ?? self.clipSegments
        let normalizedSegments = Self.normalizedClipSegments(nextSegments, duration: nextDuration)
        let nextTrimRange = trimRange ?? Self.overallTrimRange(for: normalizedSegments, duration: nextDuration)

        return RecordingProject(
            id: id,
            name: name,
            createdAt: createdAt,
            duration: nextDuration,
            sourceVideoURL: sourceVideoURL,
            reconstructsCursor: reconstructsCursor,
            events: events,
            cameraKeyframes: cameraKeyframes,
            style: style,
            trimRange: nextTrimRange,
            clipSegments: normalizedSegments,
            manualZoomSegments: manualZoomSegments ?? self.manualZoomSegments,
            zoomTrackEdited: zoomTrackEdited ?? self.zoomTrackEdited
        )
    }

    func sourceTimestamp(forClipOffset offset: TimeInterval) -> TimeInterval {
        let segments = effectiveClipSegments
        guard let first = segments.first else { return 0 }

        var remaining = offset.clamped(to: 0...trimmedDuration)
        for segment in segments {
            if remaining <= segment.duration {
                return segment.start + remaining
            }
            remaining -= segment.duration
        }

        return segments.last?.end ?? first.start
    }

    func clipOffset(forSourceTimestamp timestamp: TimeInterval) -> TimeInterval {
        let sourceTimestamp = timestamp.clamped(to: 0...duration)
        var elapsed: TimeInterval = 0
        var nearestOffset: TimeInterval = 0
        var nearestDistance = TimeInterval.greatestFiniteMagnitude

        for segment in effectiveClipSegments {
            if sourceTimestamp >= segment.start && sourceTimestamp <= segment.end {
                return elapsed + (sourceTimestamp - segment.start)
            }

            let startDistance = abs(sourceTimestamp - segment.start)
            if startDistance < nearestDistance {
                nearestDistance = startDistance
                nearestOffset = elapsed
            }

            let endDistance = abs(sourceTimestamp - segment.end)
            if endDistance < nearestDistance {
                nearestDistance = endDistance
                nearestOffset = elapsed + segment.duration
            }

            elapsed += segment.duration
        }

        return nearestOffset.clamped(to: 0...trimmedDuration)
    }

    func nearestClipSourceTimestamp(to timestamp: TimeInterval) -> TimeInterval {
        sourceTimestamp(forClipOffset: clipOffset(forSourceTimestamp: timestamp))
    }

    static func normalizedClipSegments(_ segments: [ProjectTrimRange], duration: TimeInterval) -> [ProjectTrimRange] {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else {
            return [ProjectTrimRange(start: 0, end: 0)]
        }

        let normalized = segments
            .map { $0.clamped(to: safeDuration) }
            .filter { $0.duration > 0.001 }
            .sorted { $0.start < $1.start }

        return normalized.isEmpty
            ? [ProjectTrimRange(start: 0, end: safeDuration)]
            : normalized
    }

    static func overallTrimRange(for segments: [ProjectTrimRange], duration: TimeInterval) -> ProjectTrimRange {
        let normalized = normalizedClipSegments(segments, duration: duration)
        guard let first = normalized.first, let last = normalized.last else {
            return ProjectTrimRange(start: 0, end: max(duration, 0))
        }

        return ProjectTrimRange(start: first.start, end: last.end).clamped(to: duration)
    }

    static func normalizedManualZoomSegments(_ segments: [ManualZoomSegment], duration: TimeInterval) -> [ManualZoomSegment] {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else { return [] }

        let normalized = segments
            .map { $0.clamped(to: safeDuration) }
            .filter { $0.duration >= ManualZoomSegment.minimumDuration }
            .sorted { lhs, rhs in
                if abs(lhs.start - rhs.start) > 0.0001 {
                    return lhs.start < rhs.start
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let manualSegments = normalized.filter { $0.source == .manual }
        let resolvedManuals = nonOverlappingManualSegments(manualSegments)
        let resolvedAutos = normalized
            .filter { $0.source == .auto }
            .flatMap { subtract(overlaps: resolvedManuals, from: $0) }

        return (resolvedManuals + resolvedAutos).sorted { lhs, rhs in
            if abs(lhs.start - rhs.start) > 0.0001 {
                return lhs.start < rhs.start
            }
            if lhs.source != rhs.source {
                return lhs.source == .manual
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func autoZoomSegments(from keyframes: [CameraKeyframe], duration: TimeInterval) -> [ManualZoomSegment] {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else { return [] }

        let threshold = 1.025
        let sorted = keyframes.sorted { $0.timestamp < $1.timestamp }
        var segments: [ManualZoomSegment] = []
        var activeFrames: [CameraKeyframe] = []

        func flushActiveFrames() {
            guard let first = activeFrames.first, let last = activeFrames.last else {
                activeFrames = []
                return
            }

            let start = max(first.timestamp - 0.08, 0)
            let end = min(last.timestamp + 0.22, safeDuration)
            guard end - start >= ManualZoomSegment.minimumDuration else {
                activeFrames = []
                return
            }

            let peakFrame = activeFrames.max { $0.zoom < $1.zoom } ?? last
            segments.append(
                ManualZoomSegment(
                    start: start,
                    end: end,
                    focus: peakFrame.focus,
                    zoomLevel: peakFrame.zoom.clamped(to: ManualZoomSegment.zoomRange),
                    source: .auto
                )
            )
            activeFrames = []
        }

        for frame in sorted {
            if frame.zoom > threshold {
                activeFrames.append(frame)
            } else {
                flushActiveFrames()
            }
        }
        flushActiveFrames()
        return segments
    }

    private static func nonOverlappingManualSegments(_ segments: [ManualZoomSegment]) -> [ManualZoomSegment] {
        var result: [ManualZoomSegment] = []
        for segment in segments {
            guard let previous = result.last, segment.start < previous.end else {
                result.append(segment)
                continue
            }

            let adjustedStart = previous.end
            guard segment.end - adjustedStart >= ManualZoomSegment.minimumDuration else { continue }
            result.append(segment.updating(start: adjustedStart))
        }
        return result
    }

    private static func subtract(overlaps: [ManualZoomSegment], from autoSegment: ManualZoomSegment) -> [ManualZoomSegment] {
        var remaining = [ProjectTrimRange(start: autoSegment.start, end: autoSegment.end)]
        for manual in overlaps where manual.end > autoSegment.start && manual.start < autoSegment.end {
            remaining = remaining.flatMap { range -> [ProjectTrimRange] in
                var pieces: [ProjectTrimRange] = []
                if manual.start - range.start >= ManualZoomSegment.minimumDuration {
                    pieces.append(ProjectTrimRange(start: range.start, end: min(manual.start, range.end)))
                }
                if range.end - manual.end >= ManualZoomSegment.minimumDuration {
                    pieces.append(ProjectTrimRange(start: max(manual.end, range.start), end: range.end))
                }
                return pieces
            }
        }

        return remaining.enumerated().map { index, range in
            ManualZoomSegment(
                id: index == 0 ? autoSegment.id : UUID(),
                start: range.start,
                end: range.end,
                focus: autoSegment.focus,
                zoomLevel: autoSegment.zoomLevel,
                easeInDuration: autoSegment.easeInDuration,
                easeOutDuration: autoSegment.easeOutDuration,
                source: .auto
            )
        }
    }
}

struct FileLayout {
    let root: URL
    let metadataURL: URL
    let previewDirectoryURL: URL
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
        let persistedSourceURL = try persistSourceMediaIfNeeded(from: session.rawCaptureURL, for: session.id)
        let measuredSourceDuration = sourceDuration(for: persistedSourceURL)

        let project = RecordingProject(
            id: session.id,
            name: "Demo_\(slug)",
            createdAt: createdAt,
            duration: measuredSourceDuration ?? max(session.duration, keyframes.last?.timestamp ?? 6),
            sourceVideoURL: persistedSourceURL,
            reconstructsCursor: true,
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
        try FileManager.default.createDirectory(at: layout.previewDirectoryURL, withIntermediateDirectories: true, attributes: nil)
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

    func previewDirectory(for project: RecordingProject) -> URL {
        layout(for: project.id).previewDirectoryURL
    }

    private func persistSourceMediaIfNeeded(from sourceURL: URL?, for id: UUID) throws -> URL? {
        guard let sourceURL else { return nil }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return sourceURL
        }

        let layout = layout(for: id)
        try fileManager.createDirectory(at: layout.root, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: layout.previewDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: layout.exportDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = layout.root
            .appendingPathComponent("source", isDirectory: false)
            .appendingPathExtension(fileExtension)

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return destinationURL
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func sourceDuration(for sourceURL: URL?) -> TimeInterval? {
        guard let sourceURL else { return nil }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: sourceURL).duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private func layout(for id: UUID) -> FileLayout {
        let root = rootDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        return FileLayout(
            root: root,
            metadataURL: root.appendingPathComponent("project.json"),
            previewDirectoryURL: root.appendingPathComponent("Previews", isDirectory: true),
            exportDirectoryURL: root.appendingPathComponent("Exports", isDirectory: true)
        )
    }
}
