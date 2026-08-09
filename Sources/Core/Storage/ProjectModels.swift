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

enum CursorStyle: String, CaseIterable, Codable {
    case systemArrow
    case pointerHand
    case magicWand
    case catPaw

    var label: String {
        switch self {
        case .systemArrow:
            "Default"
        case .pointerHand:
            "Pointer Hand"
        case .magicWand:
            "Magic Wand"
        case .catPaw:
            "Cat Paw"
        }
    }

    var assetName: String {
        switch self {
        case .systemArrow:
            "CursorSystemArrow"
        case .pointerHand:
            "CursorPointerHand"
        case .magicWand:
            "CursorMagicWand"
        case .catPaw:
            "CursorCatPaw"
        }
    }

    var templateSize: CGSize {
        switch self {
        case .systemArrow:
            CGSize(width: 44, height: 44)
        case .pointerHand:
            CGSize(width: 72, height: 72)
        case .magicWand:
            CGSize(width: 82, height: 82)
        case .catPaw:
            CGSize(width: 76, height: 76)
        }
    }

    var hotspot: CGPoint {
        switch self {
        case .systemArrow:
            CGPoint(x: 5, y: 5)
        case .pointerHand:
            CGPoint(x: 18, y: 11)
        case .magicWand:
            CGPoint(x: 13, y: 13)
        case .catPaw:
            CGPoint(x: 18, y: 11)
        }
    }

    var requiresFlippedPreviewImageCorrection: Bool {
        self != .systemArrow
    }
}

enum PresenterBubblePosition: String, CaseIterable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum PresenterBubbleShape: String, CaseIterable, Codable {
    case circle
    case roundedRect
}

enum PresenterSource: String, Codable, Equatable {
    case camera
    case avatarImage
}

struct PresenterBubbleStyle: Codable, Equatable {
    static let defaultValue = PresenterBubbleStyle(
        isEnabled: false,
        normalizedCenter: PresenterBubbleStyle.defaultCenter(for: .bottomRight),
        normalizedSize: 0.22,
        cornerRadiusRatio: 0.5,
        shadowOpacity: 0.24,
        source: .camera
    )

    let isEnabled: Bool
    let normalizedCenter: NormalizedPoint
    let normalizedSize: Double
    let cornerRadiusRatio: Double
    let shadowOpacity: Double
    let source: PresenterSource

    var position: PresenterBubblePosition {
        let isLeft = normalizedCenter.x < 0.5
        let isTop = normalizedCenter.y < 0.5
        switch (isTop, isLeft) {
        case (true, true):
            return .topLeft
        case (true, false):
            return .topRight
        case (false, true):
            return .bottomLeft
        case (false, false):
            return .bottomRight
        }
    }

    var shape: PresenterBubbleShape {
        cornerRadiusRatio >= 0.49 ? .circle : .roundedRect
    }

    var cornerRadius: Double {
        cornerRadiusRatio
    }

    init(
        isEnabled: Bool,
        normalizedCenter: NormalizedPoint,
        normalizedSize: Double,
        cornerRadiusRatio: Double,
        shadowOpacity: Double,
        source: PresenterSource = .camera
    ) {
        self.isEnabled = isEnabled
        self.normalizedCenter = NormalizedPoint(
            x: normalizedCenter.x.clamped(to: 0...1),
            y: normalizedCenter.y.clamped(to: 0...1)
        )
        self.normalizedSize = normalizedSize.clamped(to: 0.08...0.5)
        self.cornerRadiusRatio = cornerRadiusRatio.clamped(to: 0...0.5)
        self.shadowOpacity = shadowOpacity.clamped(to: 0...1)
        self.source = source
    }

    init(
        isEnabled: Bool,
        position: PresenterBubblePosition,
        normalizedSize: Double,
        shape: PresenterBubbleShape,
        cornerRadius: Double,
        shadowOpacity: Double,
        source: PresenterSource = .camera
    ) {
        self.init(
            isEnabled: isEnabled,
            normalizedCenter: Self.defaultCenter(for: position),
            normalizedSize: normalizedSize,
            cornerRadiusRatio: shape == .circle ? 0.5 : Self.normalizedLegacyCornerRadius(cornerRadius),
            shadowOpacity: shadowOpacity,
            source: source
        )
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case position
        case normalizedCenter
        case normalizedSize
        case shape
        case cornerRadius
        case cornerRadiusRatio
        case shadowOpacity
        case source
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyPosition = try container.decodeIfPresent(
            PresenterBubblePosition.self,
            forKey: .position
        ) ?? .bottomRight
        let legacyShape = try container.decodeIfPresent(
            PresenterBubbleShape.self,
            forKey: .shape
        ) ?? .circle
        let legacyCornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 18

        let decodedCenter = try container.decodeIfPresent(NormalizedPoint.self, forKey: .normalizedCenter)
            ?? Self.defaultCenter(for: legacyPosition)
        let decodedCornerRatio: Double
        if let ratio = try container.decodeIfPresent(Double.self, forKey: .cornerRadiusRatio) {
            decodedCornerRatio = ratio
        } else if legacyShape == .circle {
            decodedCornerRatio = 0.5
        } else {
            decodedCornerRatio = Self.normalizedLegacyCornerRadius(legacyCornerRadius)
        }

        self.init(
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            normalizedCenter: decodedCenter,
            normalizedSize: try container.decode(Double.self, forKey: .normalizedSize),
            cornerRadiusRatio: decodedCornerRatio,
            shadowOpacity: try container.decode(Double.self, forKey: .shadowOpacity),
            source: try container.decodeIfPresent(PresenterSource.self, forKey: .source) ?? .camera
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(position, forKey: .position)
        try container.encode(normalizedCenter, forKey: .normalizedCenter)
        try container.encode(normalizedSize, forKey: .normalizedSize)
        try container.encode(shape, forKey: .shape)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(cornerRadiusRatio, forKey: .cornerRadiusRatio)
        try container.encode(shadowOpacity, forKey: .shadowOpacity)
        try container.encode(source, forKey: .source)
    }

    static func defaultCenter(for position: PresenterBubblePosition) -> NormalizedPoint {
        switch position {
        case .topLeft:
            NormalizedPoint(x: 0, y: 0)
        case .topRight:
            NormalizedPoint(x: 1, y: 0)
        case .bottomLeft:
            NormalizedPoint(x: 0, y: 1)
        case .bottomRight:
            NormalizedPoint(x: 1, y: 1)
        }
    }

    private static func normalizedLegacyCornerRadius(_ value: Double) -> Double {
        let normalized = value > 1 ? value / 100 : value
        return normalized.clamped(to: 0...0.5)
    }
}

struct PresenterMedia: Codable, Equatable {
    let sourceVideoURL: URL?
    let startedAt: Date?
    let renderOffset: TimeInterval
    let naturalSize: CGSize
}

struct RecordingNotes: Codable, Equatable {
    static let defaultValue = RecordingNotes(
        text: "",
        isVisibleDuringRecording: false,
        fontScale: 1.0
    )

    let text: String
    let isVisibleDuringRecording: Bool
    let fontScale: Double

    var hasContent: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init(
        text: String,
        isVisibleDuringRecording: Bool,
        fontScale: Double
    ) {
        self.text = text
        self.isVisibleDuringRecording = isVisibleDuringRecording
        self.fontScale = fontScale.clamped(to: 0.8...1.6)
    }
}

struct ProjectStyle: Codable, Equatable {
    let aspectRatio: ProjectAspectRatio
    let backgroundPresetID: String
    let cornerRadius: Double
    let shadowRadius: Double
    let followStrength: Double
    let clickEmphasis: Double
    let padding: Double
    let presenterBubbleStyle: PresenterBubbleStyle
    let cursorStyle: CursorStyle

    var backgroundPreset: BackgroundPreset {
        BackgroundPresetCatalog.preset(id: backgroundPresetID)
    }

    var background: ProjectBackgroundStyle {
        BackgroundPresetCatalog.legacyStyle(forPresetID: backgroundPresetID)
    }

    enum CodingKeys: String, CodingKey {
        case aspectRatio
        case backgroundPresetID
        case background
        case cornerRadius
        case shadowRadius
        case followStrength
        case clickEmphasis
        case padding
        case presenterBubbleStyle
        case cursorStyle
    }

    init(
        aspectRatio: ProjectAspectRatio,
        backgroundPresetID: String,
        cornerRadius: Double,
        shadowRadius: Double,
        followStrength: Double,
        clickEmphasis: Double,
        padding: Double,
        presenterBubbleStyle: PresenterBubbleStyle = .defaultValue,
        cursorStyle: CursorStyle = .systemArrow
    ) {
        self.aspectRatio = aspectRatio
        self.backgroundPresetID = backgroundPresetID
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.followStrength = followStrength
        self.clickEmphasis = clickEmphasis
        self.padding = padding
        self.presenterBubbleStyle = presenterBubbleStyle
        self.cursorStyle = cursorStyle
    }

    init(
        aspectRatio: ProjectAspectRatio,
        background: ProjectBackgroundStyle,
        cornerRadius: Double,
        shadowRadius: Double,
        followStrength: Double,
        clickEmphasis: Double,
        padding: Double,
        presenterBubbleStyle: PresenterBubbleStyle = .defaultValue,
        cursorStyle: CursorStyle = .systemArrow
    ) {
        self.init(
            aspectRatio: aspectRatio,
            backgroundPresetID: BackgroundPresetCatalog.legacyPresetID(for: background),
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            followStrength: followStrength,
            clickEmphasis: clickEmphasis,
            padding: padding,
            presenterBubbleStyle: presenterBubbleStyle,
            cursorStyle: cursorStyle
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aspectRatio = try container.decode(ProjectAspectRatio.self, forKey: .aspectRatio)
        let backgroundPresetID: String
        if let presetID = try container.decodeIfPresent(String.self, forKey: .backgroundPresetID) {
            backgroundPresetID = presetID
        } else {
            let legacy = try container.decode(ProjectBackgroundStyle.self, forKey: .background)
            backgroundPresetID = BackgroundPresetCatalog.legacyPresetID(for: legacy)
        }

        self.init(
            aspectRatio: aspectRatio,
            backgroundPresetID: backgroundPresetID,
            cornerRadius: try container.decode(Double.self, forKey: .cornerRadius),
            shadowRadius: try container.decode(Double.self, forKey: .shadowRadius),
            followStrength: try container.decode(Double.self, forKey: .followStrength),
            clickEmphasis: try container.decode(Double.self, forKey: .clickEmphasis),
            padding: try container.decode(Double.self, forKey: .padding),
            presenterBubbleStyle: try container.decodeIfPresent(
                PresenterBubbleStyle.self,
                forKey: .presenterBubbleStyle
            ) ?? .defaultValue,
            cursorStyle: try container.decodeIfPresent(CursorStyle.self, forKey: .cursorStyle) ?? .systemArrow
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(backgroundPresetID, forKey: .backgroundPresetID)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(shadowRadius, forKey: .shadowRadius)
        try container.encode(followStrength, forKey: .followStrength)
        try container.encode(clickEmphasis, forKey: .clickEmphasis)
        try container.encode(padding, forKey: .padding)
        try container.encode(presenterBubbleStyle, forKey: .presenterBubbleStyle)
        try container.encode(cursorStyle, forKey: .cursorStyle)
    }
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
    let sourceVisibleRect: CaptureViewport?
    let captureTarget: CaptureTarget
    let reconstructsCursor: Bool
    let events: [PointerEvent]
    let cameraKeyframes: [CameraKeyframe]
    let style: ProjectStyle
    let trimRange: ProjectTrimRange
    let clipSegments: [ProjectTrimRange]
    let manualZoomSegments: [ManualZoomSegment]
    let zoomTrackEdited: Bool
    let presenterMedia: PresenterMedia?
    let captionTrack: CaptionTrack?
    let recordingNotes: RecordingNotes?

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

    func effectiveSourceExtent(for sourceExtent: CGRect) -> CGRect {
        guard let sourceVisibleRect else { return sourceExtent }
        let visibleRect = sourceVisibleRect.rect
        guard visibleRect.width > 0,
              visibleRect.height > 0,
              sourceExtent.contains(visibleRect) else {
            return sourceExtent
        }
        return visibleRect
    }

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        duration: TimeInterval,
        sourceVideoURL: URL?,
        sourceVisibleRect: CaptureViewport? = nil,
        captureTarget: CaptureTarget = .screen,
        reconstructsCursor: Bool = false,
        events: [PointerEvent],
        cameraKeyframes: [CameraKeyframe],
        style: ProjectStyle,
        trimRange: ProjectTrimRange? = nil,
        clipSegments: [ProjectTrimRange]? = nil,
        manualZoomSegments: [ManualZoomSegment] = [],
        zoomTrackEdited: Bool = false,
        presenterMedia: PresenterMedia? = nil,
        captionTrack: CaptionTrack? = nil,
        recordingNotes: RecordingNotes? = nil
    ) {
        let safeDuration = max(duration, 0)
        let safeTrimRange = (trimRange ?? ProjectTrimRange(start: 0, end: safeDuration)).clamped(to: safeDuration)
        let proposedZoomSegments = manualZoomSegments.isEmpty && zoomTrackEdited == false
            ? Self.autoZoomSegments(from: events, keyframes: cameraKeyframes, duration: safeDuration)
            : manualZoomSegments
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = safeDuration
        self.sourceVideoURL = sourceVideoURL
        self.sourceVisibleRect = sourceVisibleRect
        self.captureTarget = captureTarget
        self.reconstructsCursor = reconstructsCursor
        self.events = events
        self.cameraKeyframes = cameraKeyframes
        self.style = style
        self.trimRange = safeTrimRange
        self.clipSegments = Self.normalizedClipSegments(clipSegments ?? [safeTrimRange], duration: safeDuration)
        self.manualZoomSegments = Self.normalizedManualZoomSegments(proposedZoomSegments, duration: safeDuration)
        self.zoomTrackEdited = zoomTrackEdited
        self.presenterMedia = presenterMedia
        self.captionTrack = captionTrack
        self.recordingNotes = recordingNotes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case duration
        case sourceVideoURL
        case sourceVisibleRect
        case captureTarget
        case reconstructsCursor
        case events
        case cameraKeyframes
        case style
        case trimRange
        case clipSegments
        case manualZoomSegments
        case zoomTrackEdited
        case presenterMedia
        case captionTrack
        case recordingNotes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let duration = try container.decode(TimeInterval.self, forKey: .duration)
        let sourceVideoURL = try container.decodeIfPresent(URL.self, forKey: .sourceVideoURL)
        let sourceVisibleRect = try container.decodeIfPresent(CaptureViewport.self, forKey: .sourceVisibleRect)
        let captureTarget = try container.decodeIfPresent(CaptureTarget.self, forKey: .captureTarget) ?? .screen
        let reconstructsCursor = try container.decodeIfPresent(Bool.self, forKey: .reconstructsCursor) ?? false
        let events = try container.decode([PointerEvent].self, forKey: .events)
        let cameraKeyframes = try container.decode([CameraKeyframe].self, forKey: .cameraKeyframes)
        let style = try container.decode(ProjectStyle.self, forKey: .style)
        let trimRange = try container.decodeIfPresent(ProjectTrimRange.self, forKey: .trimRange)
        let clipSegments = try container.decodeIfPresent([ProjectTrimRange].self, forKey: .clipSegments)
        let manualZoomSegments = try container.decodeIfPresent([ManualZoomSegment].self, forKey: .manualZoomSegments) ?? []
        let zoomTrackEdited = try container.decodeIfPresent(Bool.self, forKey: .zoomTrackEdited) ?? false
        let presenterMedia = try container.decodeIfPresent(PresenterMedia.self, forKey: .presenterMedia)
        let captionTrack = try container.decodeIfPresent(CaptionTrack.self, forKey: .captionTrack)
        let recordingNotes = try container.decodeIfPresent(RecordingNotes.self, forKey: .recordingNotes)

        self.init(
            id: id,
            name: name,
            createdAt: createdAt,
            duration: duration,
            sourceVideoURL: sourceVideoURL,
            sourceVisibleRect: sourceVisibleRect,
            captureTarget: captureTarget,
            reconstructsCursor: reconstructsCursor,
            events: events,
            cameraKeyframes: cameraKeyframes,
            style: style,
            trimRange: trimRange,
            clipSegments: clipSegments,
            manualZoomSegments: manualZoomSegments,
            zoomTrackEdited: zoomTrackEdited,
            presenterMedia: presenterMedia,
            captionTrack: captionTrack,
            recordingNotes: recordingNotes
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(sourceVideoURL, forKey: .sourceVideoURL)
        try container.encodeIfPresent(sourceVisibleRect, forKey: .sourceVisibleRect)
        try container.encode(captureTarget, forKey: .captureTarget)
        try container.encode(reconstructsCursor, forKey: .reconstructsCursor)
        try container.encode(events, forKey: .events)
        try container.encode(cameraKeyframes, forKey: .cameraKeyframes)
        try container.encode(style, forKey: .style)
        try container.encode(trimRange, forKey: .trimRange)
        try container.encode(clipSegments, forKey: .clipSegments)
        try container.encode(manualZoomSegments, forKey: .manualZoomSegments)
        try container.encode(zoomTrackEdited, forKey: .zoomTrackEdited)
        try container.encodeIfPresent(presenterMedia, forKey: .presenterMedia)
        try container.encodeIfPresent(captionTrack, forKey: .captionTrack)
        try container.encodeIfPresent(recordingNotes, forKey: .recordingNotes)
    }

    func updating(
        style: ProjectStyle,
        cameraKeyframes: [CameraKeyframe],
        duration: TimeInterval? = nil,
        trimRange: ProjectTrimRange? = nil,
        clipSegments: [ProjectTrimRange]? = nil,
        manualZoomSegments: [ManualZoomSegment]? = nil,
        zoomTrackEdited: Bool? = nil,
        presenterMedia: PresenterMedia? = nil,
        captionTrack: CaptionTrack? = nil,
        recordingNotes: RecordingNotes? = nil
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
            sourceVisibleRect: sourceVisibleRect,
            captureTarget: captureTarget,
            reconstructsCursor: reconstructsCursor,
            events: events,
            cameraKeyframes: cameraKeyframes,
            style: style,
            trimRange: nextTrimRange,
            clipSegments: normalizedSegments,
            manualZoomSegments: manualZoomSegments ?? self.manualZoomSegments,
            zoomTrackEdited: zoomTrackEdited ?? self.zoomTrackEdited,
            presenterMedia: presenterMedia ?? self.presenterMedia,
            captionTrack: captionTrack ?? self.captionTrack,
            recordingNotes: recordingNotes ?? self.recordingNotes
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

    static func autoZoomSegments(from events: [PointerEvent], keyframes: [CameraKeyframe], duration: TimeInterval) -> [ManualZoomSegment] {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else { return [] }

        let clickEvents = events
            .filter { $0.type == .click }
            .sorted { $0.timestamp < $1.timestamp }
        guard clickEvents.isEmpty == false else { return [] }

        let composer = FrameComposer()
        let anticipation: TimeInterval = 0.08
        let easeInDuration = ManualZoomSegment.defaultEaseDuration
        let tail: TimeInterval = 2.2
        let settleOffset: TimeInterval = 0.55

        return clickEvents.enumerated().compactMap { index, click in
            let start = max(click.timestamp - anticipation, 0)
            let naturalEnd = min(click.timestamp + tail, safeDuration)
            let nextStart = clickEvents.indices.contains(index + 1)
                ? max(clickEvents[index + 1].timestamp - anticipation, 0)
                : safeDuration
            let end = min(naturalEnd, nextStart)
            guard end - start >= ManualZoomSegment.minimumDuration else { return nil }

            let settledSnapshot = composer.snapshot(
                at: min(click.timestamp + settleOffset, safeDuration),
                from: keyframes
            )
            let zoomLevel = max(settledSnapshot.zoom, 1.28)
                .clamped(to: ManualZoomSegment.zoomRange)

            return ManualZoomSegment(
                start: start,
                end: end,
                focus: click.location,
                zoomLevel: zoomLevel,
                easeInDuration: easeInDuration,
                easeOutDuration: 0,
                source: .auto
            )
        }
    }

    static func autoZoomSegments(from keyframes: [CameraKeyframe], duration: TimeInterval) -> [ManualZoomSegment] {
        autoZoomSegments(from: [], keyframes: keyframes, duration: duration)
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
    let coordinateDiagnosticsURL: URL
    let previewDirectoryURL: URL
    let exportDirectoryURL: URL
}

struct CoordinateDiagnostics: Codable, Equatable {
    struct EventSample: Codable, Equatable {
        let id: UUID
        let timestamp: TimeInterval
        let type: PointerEventType
        let legacyNormalizedLocation: NormalizedPoint
        let globalLocation: PointerGlobalLocation?
        let diagnostics: PointerEventDiagnostics?
    }

    struct NormalizedSample: Codable, Equatable {
        let id: UUID
        let timestamp: TimeInterval
        let type: PointerEventType
        let location: NormalizedPoint
        let globalLocation: PointerGlobalLocation?
        let diagnostics: PointerEventDiagnostics?
    }

    struct ClickAlignment: Codable, Equatable {
        let id: UUID
        let timestamp: TimeInterval
        let clickLocation: NormalizedPoint
        let cameraFocusAtClick: NormalizedPoint
        let cameraFocusAfterSettle: NormalizedPoint
        let renderedFocusAtClick: NormalizedPoint
        let renderedFocusAfterSettle: NormalizedPoint
        let focusOffsetAtClick: Double
        let focusOffsetAfterSettle: Double
        let renderedFocusOffsetAtClick: Double
        let renderedFocusOffsetAfterSettle: Double
    }

    struct SourceClickMapping: Codable, Equatable {
        let id: UUID
        let timestamp: TimeInterval
        let normalizedLocation: NormalizedPoint
        let sourcePixelLocation: SourcePixelLocation
    }

    struct SourcePixelLocation: Codable, Equatable {
        let x: Double
        let y: Double
    }

    let projectID: UUID
    let captureTarget: CaptureTarget
    let coordinateSpace: CaptureCoordinateSpace?
    let sourceFrameSize: CGSize?
    let sourceVisibleRect: CaptureViewport?
    let windowDiagnostics: CaptureWindowDiagnostics?
    let sessionStartedAt: Date
    let mediaStartedAt: Date?
    let pointerTimelineOffset: TimeInterval
    let sessionDuration: TimeInterval
    let projectDuration: TimeInterval
    let rawEventCount: Int
    let normalizedEventCount: Int
    let rawClickCount: Int
    let normalizedClickCount: Int
    let rawClicks: [EventSample]
    let normalizedClicks: [NormalizedSample]
    let droppedClicks: [EventSample]
    let sourceClickMappings: [SourceClickMapping]
    let clickAlignments: [ClickAlignment]
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
        rawEvents: [PointerEvent] = [],
        events: [PointerEvent],
        keyframes: [CameraKeyframe],
        style: ProjectStyle,
        presenterMedia: PresenterMedia? = nil,
        recordingNotes: RecordingNotes? = nil
    ) throws -> RecordingProject {
        let createdAt = Date()
        let slug = createdAt.formatted(.dateTime.year().month().day().hour().minute())
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        let persistedSourceURL = try persistSourceMediaIfNeeded(from: session.rawCaptureURL, for: session.id)
        let persistedPresenterMedia = try persistPresenterMediaIfNeeded(presenterMedia, for: session.id)
        let measuredSourceDuration = sourceDuration(for: persistedSourceURL)

        let project = RecordingProject(
            id: session.id,
            name: "Demo_\(slug)",
            createdAt: createdAt,
            duration: measuredSourceDuration ?? max(session.duration, keyframes.last?.timestamp ?? 6),
            sourceVideoURL: persistedSourceURL,
            sourceVisibleRect: session.sourceVisibleRect,
            captureTarget: session.configuration.target,
            reconstructsCursor: true,
            events: events,
            cameraKeyframes: keyframes,
            style: style,
            presenterMedia: persistedPresenterMedia,
            recordingNotes: recordingNotes
        )

        try save(project: project)
        try saveCoordinateDiagnostics(
            for: project,
            session: session,
            rawEvents: rawEvents,
            normalizedEvents: events,
            keyframes: keyframes
        )
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

    func coordinateDiagnosticsURL(for project: RecordingProject) -> URL {
        layout(for: project.id).coordinateDiagnosticsURL
    }

    private func saveCoordinateDiagnostics(
        for project: RecordingProject,
        session: CaptureSession,
        rawEvents: [PointerEvent],
        normalizedEvents: [PointerEvent],
        keyframes: [CameraKeyframe]
    ) throws {
        let layout = layout(for: project.id)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true, attributes: nil)

        let rawClicks = rawEvents.filter { $0.type == .click }
        let normalizedClicks = normalizedEvents.filter { $0.type == .click }
        let normalizedClickIDs = Set(normalizedClicks.map(\.id))
        let composer = FrameComposer()
        let diagnostics = CoordinateDiagnostics(
            projectID: project.id,
            captureTarget: session.configuration.target,
            coordinateSpace: session.coordinateSpace,
            sourceFrameSize: session.sourceFrameSize,
            sourceVisibleRect: session.sourceVisibleRect,
            windowDiagnostics: session.windowDiagnostics,
            sessionStartedAt: session.startedAt,
            mediaStartedAt: session.mediaStartedAt,
            pointerTimelineOffset: session.mediaStartedAt?.timeIntervalSince(session.startedAt) ?? 0,
            sessionDuration: session.duration,
            projectDuration: project.duration,
            rawEventCount: rawEvents.count,
            normalizedEventCount: normalizedEvents.count,
            rawClickCount: rawClicks.count,
            normalizedClickCount: normalizedClicks.count,
            rawClicks: rawClicks.map(Self.eventSample),
            normalizedClicks: normalizedClicks.map(Self.normalizedSample),
            droppedClicks: rawClicks
                .filter { normalizedClickIDs.contains($0.id) == false }
                .map(Self.eventSample),
            sourceClickMappings: Self.sourceClickMappings(
                from: normalizedClicks,
                sourceVisibleRect: session.sourceVisibleRect
            ),
            clickAlignments: normalizedClicks.map { click in
                let atClick = composer.snapshot(at: click.timestamp, from: keyframes)
                let afterSettle = composer.snapshot(at: click.timestamp + 0.55, from: keyframes)
                let renderedAtClick = composer.snapshot(
                    at: click.timestamp,
                    from: keyframes,
                    manualZoomSegments: project.manualZoomSegments,
                    zoomTrackEdited: project.zoomTrackEdited
                )
                let renderedAfterSettle = composer.snapshot(
                    at: click.timestamp + 0.55,
                    from: keyframes,
                    manualZoomSegments: project.manualZoomSegments,
                    zoomTrackEdited: project.zoomTrackEdited
                )
                return CoordinateDiagnostics.ClickAlignment(
                    id: click.id,
                    timestamp: click.timestamp,
                    clickLocation: click.location,
                    cameraFocusAtClick: atClick.focus,
                    cameraFocusAfterSettle: afterSettle.focus,
                    renderedFocusAtClick: renderedAtClick.focus,
                    renderedFocusAfterSettle: renderedAfterSettle.focus,
                    focusOffsetAtClick: Self.distance(from: click.location, to: atClick.focus),
                    focusOffsetAfterSettle: Self.distance(from: click.location, to: afterSettle.focus),
                    renderedFocusOffsetAtClick: Self.distance(from: click.location, to: renderedAtClick.focus),
                    renderedFocusOffsetAfterSettle: Self.distance(from: click.location, to: renderedAfterSettle.focus)
                )
            }
        )

        let data = try encoder.encode(diagnostics)
        try data.write(to: layout.coordinateDiagnosticsURL, options: .atomic)
    }

    private static func sourceClickMappings(
        from clicks: [PointerEvent],
        sourceVisibleRect: CaptureViewport?
    ) -> [CoordinateDiagnostics.SourceClickMapping] {
        guard let visibleRect = sourceVisibleRect?.rect,
              visibleRect.width > 0,
              visibleRect.height > 0 else {
            return []
        }

        return clicks.map { click in
            CoordinateDiagnostics.SourceClickMapping(
                id: click.id,
                timestamp: click.timestamp,
                normalizedLocation: click.location,
                sourcePixelLocation: CoordinateDiagnostics.SourcePixelLocation(
                    x: visibleRect.minX + (click.location.x * visibleRect.width),
                    y: visibleRect.minY + (click.location.y * visibleRect.height)
                )
            )
        }
    }

    private static func eventSample(_ event: PointerEvent) -> CoordinateDiagnostics.EventSample {
        CoordinateDiagnostics.EventSample(
            id: event.id,
            timestamp: event.timestamp,
            type: event.type,
            legacyNormalizedLocation: event.location,
            globalLocation: event.globalLocation,
            diagnostics: event.diagnostics
        )
    }

    private static func normalizedSample(_ event: PointerEvent) -> CoordinateDiagnostics.NormalizedSample {
        CoordinateDiagnostics.NormalizedSample(
            id: event.id,
            timestamp: event.timestamp,
            type: event.type,
            location: event.location,
            globalLocation: event.globalLocation,
            diagnostics: event.diagnostics
        )
    }

    private static func distance(from lhs: NormalizedPoint, to rhs: NormalizedPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt((dx * dx) + (dy * dy))
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

    private func persistPresenterMediaIfNeeded(_ media: PresenterMedia?, for id: UUID) throws -> PresenterMedia? {
        guard let media, let sourceURL = media.sourceVideoURL else { return media }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let layout = layout(for: id)
        try fileManager.createDirectory(at: layout.root, withIntermediateDirectories: true, attributes: nil)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = layout.root
            .appendingPathComponent("presenter", isDirectory: false)
            .appendingPathExtension(fileExtension)

        if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return PresenterMedia(
            sourceVideoURL: destinationURL,
            startedAt: media.startedAt,
            renderOffset: media.renderOffset,
            naturalSize: media.naturalSize
        )
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
            coordinateDiagnosticsURL: root.appendingPathComponent("coordinate-diagnostics.json"),
            previewDirectoryURL: root.appendingPathComponent("Previews", isDirectory: true),
            exportDirectoryURL: root.appendingPathComponent("Exports", isDirectory: true)
        )
    }
}
