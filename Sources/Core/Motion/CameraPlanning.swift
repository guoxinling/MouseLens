import Foundation

struct CameraKeyframe: Identifiable, Codable, Equatable {
    enum EmphasisKind: String, Codable {
        case none
        case click
    }

    let id: UUID
    let timestamp: TimeInterval
    let focus: NormalizedPoint
    let zoom: Double
    let emphasis: EmphasisKind

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        focus: NormalizedPoint,
        zoom: Double,
        emphasis: EmphasisKind = .none
    ) {
        self.id = id
        self.timestamp = timestamp
        self.focus = focus
        self.zoom = zoom
        self.emphasis = emphasis
    }
}

struct SmoothingFilter {
    let alpha: Double

    func apply(current: NormalizedPoint, target: NormalizedPoint) -> NormalizedPoint {
        let x = current.x + ((target.x - current.x) * alpha)
        let y = current.y + ((target.y - current.y) * alpha)
        return NormalizedPoint(x: x, y: y)
    }
}

struct ClickEmphasisRule: Equatable {
    let boost: Double
    let duration: TimeInterval
}

final class CameraPlanEngine {
    func makePlan(
        from events: [PointerEvent],
        baseZoom: Double,
        followStrength: Double,
        clickRule: ClickEmphasisRule
    ) -> [CameraKeyframe] {
        guard !events.isEmpty else {
            return [CameraKeyframe(timestamp: 0, focus: .center, zoom: baseZoom)]
        }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let filter = SmoothingFilter(alpha: smoothingAlpha(for: followStrength))
        var smoothed = sorted.first?.location ?? .center
        let clickTimes = sorted.filter { $0.type == .click }.map(\.timestamp)
        var keyframes: [CameraKeyframe] = []

        if let first = sorted.first, first.timestamp > 0 {
            keyframes.append(
                CameraKeyframe(timestamp: 0, focus: first.location, zoom: baseZoom, emphasis: .none)
            )
        }

        for event in sorted {
            let target = targetFocus(for: event.location)
            smoothed = filter.apply(current: smoothed, target: target)

            let zoom = baseZoom + zoomBoost(at: event.timestamp, clickTimes: clickTimes, rule: clickRule)
            keyframes.append(
                CameraKeyframe(
                    timestamp: event.timestamp,
                    focus: smoothed,
                    zoom: zoom.clamped(to: 1.0...1.95),
                    emphasis: event.type == .click ? .click : .none
                )
            )
        }

        if let last = keyframes.last {
            let settleTimestamp = last.timestamp + 0.45
            keyframes.append(
                CameraKeyframe(
                    timestamp: settleTimestamp,
                    focus: filter.apply(current: last.focus, target: targetFocus(for: last.focus)),
                    zoom: max(baseZoom, last.zoom - (clickRule.boost * 0.55)),
                    emphasis: .none
                )
            )
        }

        return keyframes
    }

    private func smoothingAlpha(for followStrength: Double) -> Double {
        let clamped = followStrength.clamped(to: 0.2...1.0)
        return (0.10 + (clamped * 0.22)).clamped(to: 0.10...0.32)
    }

    private func targetFocus(for point: NormalizedPoint) -> NormalizedPoint {
        let horizontalInset = 0.08
        let topInset = 0.12
        let bottomInset = 0.16

        return NormalizedPoint(
            x: point.x.clamped(to: horizontalInset...(1 - horizontalInset)),
            y: point.y.clamped(to: topInset...(1 - bottomInset))
        )
    }

    private func zoomBoost(at timestamp: TimeInterval, clickTimes: [TimeInterval], rule: ClickEmphasisRule) -> Double {
        guard let nearestClick = clickTimes.last(where: { timestamp >= $0 }) else {
            return 0
        }

        let delta = timestamp - nearestClick
        guard delta <= rule.duration else {
            return 0
        }

        let progress = 1 - (delta / rule.duration)
        return rule.boost * progress
    }
}
