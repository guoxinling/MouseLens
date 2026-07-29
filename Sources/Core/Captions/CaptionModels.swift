import Foundation

enum CaptionPosition: String, Codable, Equatable, CaseIterable {
    case top
    case center
    case bottom
}

struct CaptionStyle: Codable, Equatable {
    static let defaultValue = CaptionStyle(
        position: .bottom,
        fontScale: 1.0,
        textColorHex: "#FFFFFF",
        backgroundOpacity: 0.56
    )

    let position: CaptionPosition
    let fontScale: Double
    let textColorHex: String
    let backgroundOpacity: Double

    init(
        position: CaptionPosition = .bottom,
        fontScale: Double = 1.0,
        textColorHex: String = "#FFFFFF",
        backgroundOpacity: Double = 0.56
    ) {
        self.position = position
        self.fontScale = fontScale.clamped(to: 0.6...1.8)
        self.textColorHex = textColorHex
        self.backgroundOpacity = backgroundOpacity.clamped(to: 0...1)
    }
}

struct CaptionSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    var duration: TimeInterval {
        max(end - start, 0)
    }

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) {
        self.id = id
        self.start = max(start, 0)
        self.end = max(end, start)
        self.text = text
    }

    func contains(_ timestamp: TimeInterval) -> Bool {
        timestamp >= start && timestamp < end
    }

    func overlaps(start overlapStart: TimeInterval, end overlapEnd: TimeInterval) -> Bool {
        self.end > overlapStart && self.start < overlapEnd
    }
}

struct CaptionTrack: Codable, Equatable {
    let isEnabled: Bool
    let localeIdentifier: String
    let segments: [CaptionSegment]
    let style: CaptionStyle

    init(
        isEnabled: Bool = true,
        localeIdentifier: String = Locale.current.identifier,
        segments: [CaptionSegment] = [],
        style: CaptionStyle = .defaultValue
    ) {
        self.isEnabled = isEnabled
        self.localeIdentifier = localeIdentifier
        self.segments = segments.sorted { lhs, rhs in
            if abs(lhs.start - rhs.start) > 0.0001 {
                return lhs.start < rhs.start
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        self.style = style
    }

    func segment(at timestamp: TimeInterval) -> CaptionSegment? {
        segments.first { $0.contains(timestamp) }
    }

    func segments(overlappingStart start: TimeInterval, end: TimeInterval) -> [CaptionSegment] {
        guard end > start else { return [] }
        return segments.filter { $0.overlaps(start: start, end: end) }
    }
}
