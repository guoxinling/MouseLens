import CoreGraphics
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

struct CaptionLayout: Equatable {
    private static let referenceContentShortSide: CGFloat = 900
    private static let baseFontSize: CGFloat = 20

    let text: String
    let position: CGPoint
    let maxTextWidth: CGFloat
    let fontSize: CGFloat
    let textColorHex: String
    let backgroundOpacity: Double
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    static func layout(
        for segment: CaptionSegment,
        style: CaptionStyle,
        contentRect: CGRect
    ) -> CaptionLayout {
        let inset = max(contentRect.height * 0.08, 28)
        let position: CGPoint
        switch style.position {
        case .top:
            position = CGPoint(x: contentRect.midX, y: contentRect.minY + inset)
        case .center:
            position = CGPoint(x: contentRect.midX, y: contentRect.midY)
        case .bottom:
            position = CGPoint(x: contentRect.midX, y: contentRect.maxY - inset)
        }
        let shortSide = min(contentRect.width, contentRect.height)
        let canvasScale = (shortSide / referenceContentShortSide).clamped(to: 0.9...2.4)

        return CaptionLayout(
            text: segment.text,
            position: position,
            maxTextWidth: max(contentRect.width * 0.72, 1),
            fontSize: baseFontSize * CGFloat(style.fontScale) * canvasScale,
            textColorHex: style.textColorHex,
            backgroundOpacity: style.backgroundOpacity,
            cornerRadius: 10,
            horizontalPadding: 14,
            verticalPadding: 8
        )
    }
}
