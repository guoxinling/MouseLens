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
    private struct CandidateRegion {
        var center: NormalizedPoint
        var accumulatedWeight: Double
        var firstSeenAt: TimeInterval
        var lastSeenAt: TimeInterval
        var clickCount: Int

        mutating func absorb(point: NormalizedPoint, weight: Double, isClick: Bool, timestamp: TimeInterval) {
            let blendAlpha = (0.22 + (weight * 0.18)).clamped(to: 0.22...0.55)
            center = center.blended(toward: point, alpha: blendAlpha)
            accumulatedWeight += weight
            lastSeenAt = timestamp
            if isClick {
                clickCount += 1
            }
        }

        var dwellDuration: TimeInterval {
            lastSeenAt - firstSeenAt
        }
    }

    private struct Shot {
        var anchor: NormalizedPoint
        var targetZoom: Double
        var startedAt: TimeInterval
    }

    private struct ShotTransition {
        var sourceFocus: NormalizedPoint
        var sourceZoom: Double
        var targetFocus: NormalizedPoint
        var targetZoom: Double
        var startedAt: TimeInterval
        var duration: TimeInterval

        func focus(at timestamp: TimeInterval) -> NormalizedPoint {
            sourceFocus.blended(toward: targetFocus, alpha: easedProgress(at: timestamp))
        }

        func zoom(at timestamp: TimeInterval) -> Double {
            let progress = easedProgress(at: timestamp)
            return sourceZoom + ((targetZoom - sourceZoom) * progress)
        }

        func isComplete(at timestamp: TimeInterval) -> Bool {
            progress(at: timestamp) >= 1
        }

        private func easedProgress(at timestamp: TimeInterval) -> Double {
            let t = progress(at: timestamp)
            return t * t * t * (t * ((t * 6) - 15) + 10)
        }

        private func progress(at timestamp: TimeInterval) -> Double {
            ((timestamp - startedAt) / max(duration, 0.0001)).clamped(to: 0...1)
        }
    }

    private struct ShotComposition {
        var focus: NormalizedPoint
        var zoom: Double
    }

    private enum ShotPhase {
        case idle
        case transitioning
        case holding

        var allowsWithinShotLead: Bool {
            switch self {
            case .idle, .holding:
                true
            case .transitioning:
                false
            }
        }
    }

    private struct ShotState {
        var shot: Shot
        var phase: ShotPhase
        var transition: ShotTransition?

        var anchor: NormalizedPoint {
            shot.anchor
        }

        var targetZoom: Double {
            shot.targetZoom
        }

        mutating func commit(
            anchor: NormalizedPoint,
            targetZoom: Double,
            timestamp: TimeInterval,
            sourceFocus: NormalizedPoint,
            sourceZoom: Double,
            transitionDuration: TimeInterval
        ) {
            shot = Shot(anchor: anchor, targetZoom: targetZoom, startedAt: timestamp)
            transition = ShotTransition(
                sourceFocus: sourceFocus,
                sourceZoom: sourceZoom,
                targetFocus: anchor,
                targetZoom: targetZoom,
                startedAt: timestamp,
                duration: transitionDuration
            )
            phase = .transitioning
        }

        mutating func updatePhase(at timestamp: TimeInterval) {
            guard case .transitioning = phase else { return }
            guard let transition else {
                phase = .holding
                return
            }

            if transition.isComplete(at: timestamp) {
                self.transition = nil
                phase = .holding
            }
        }

        func canCommit(at timestamp: TimeInterval, minimumHold: TimeInterval) -> Bool {
            switch phase {
            case .idle:
                true
            case .transitioning:
                false
            case .holding:
                timestamp - shot.startedAt >= minimumHold
            }
        }

        func composition(at timestamp: TimeInterval) -> ShotComposition {
            if case .transitioning = phase, let transition {
                return ShotComposition(
                    focus: transition.focus(at: timestamp),
                    zoom: transition.zoom(at: timestamp)
                )
            }

            return ShotComposition(focus: shot.anchor, zoom: shot.targetZoom)
        }
    }

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
        let clampedStrength = followStrength.clamped(to: 0.2...1.0)
        let sampleInterval = samplingInterval(for: clampedStrength)
        let settleDuration = idleReturnTailDuration(for: clampedStrength)
        let lastEventTime = sorted.last?.timestamp ?? 0
        let endTime = lastEventTime + settleDuration
        guard let firstClick = sorted.first(where: { $0.type == .click }) else {
            return fullViewPlan(endTime: endTime, sampleInterval: sampleInterval, baseZoom: baseZoom)
        }

        var shotState = ShotState(
            shot: Shot(
                anchor: .center,
                targetZoom: baseZoom,
                startedAt: 0
            ),
            phase: .idle,
            transition: nil
        )
        let shotTransitionDuration = shotTransitionDuration(for: clampedStrength)
        let minimumShotHold = minimumShotHold(for: clampedStrength)
        let baseCameraSmoothingAlpha = cameraSmoothingAlpha(for: clampedStrength)
        let baseLeadSmoothingAlpha = withinShotLeadAlpha(for: clampedStrength)
        let baseZoomSmoothingAlpha = zoomSmoothingAlpha(for: clampedStrength)
        var cameraFocus = NormalizedPoint.center
        var shotLead = NormalizedPoint.center
        var zoom = baseZoom
        var candidate: CandidateRegion?
        var cameraActivated = false
        var keyframes: [CameraKeyframe] = []
        var previousSampleTime = -0.0001
        var sampleTime = 0.0
        var lastActivityTime = firstClick.timestamp

        while sampleTime <= endTime + 0.0001 {
            let eventsInWindow = sorted.filter { $0.timestamp > previousSampleTime && $0.timestamp <= sampleTime }

            for event in eventsInWindow {
                guard event.timestamp >= firstClick.timestamp else { continue }
                lastActivityTime = event.timestamp
                shotState.updatePhase(at: event.timestamp)
                let eventPoint = targetFocus(for: event.location)

                if cameraActivated == false, event.type == .click {
                    let targetZoom = shotTargetZoom(
                        baseZoom: baseZoom,
                        transitionDistance: distance(from: NormalizedPoint.center, to: eventPoint),
                        followStrength: clampedStrength,
                        clickRule: clickRule
                    )
                    shotState.commit(
                        anchor: eventPoint,
                        targetZoom: targetZoom,
                        timestamp: event.timestamp,
                        sourceFocus: .center,
                        sourceZoom: baseZoom,
                        transitionDuration: shotTransitionDuration
                    )
                    cameraActivated = true
                    candidate = nil
                    shotLead = .center
                    continue
                }

                guard cameraActivated, event.type != .move else { continue }
                candidate = updateCandidate(
                    with: event,
                    point: eventPoint,
                    currentAnchor: shotState.anchor,
                    candidate: candidate,
                    followStrength: clampedStrength
                )

                if let committed = committedCandidate(
                    candidate,
                    currentAnchor: shotState.anchor,
                    currentTime: event.timestamp,
                    shotState: shotState,
                    minimumHold: minimumShotHold,
                    followStrength: clampedStrength
                ) {
                    let transitionDistance = distance(from: shotState.anchor, to: committed.center)
                    let targetZoom = shotTargetZoom(
                        baseZoom: baseZoom,
                        transitionDistance: transitionDistance,
                        followStrength: clampedStrength,
                        clickRule: clickRule
                    )
                    shotState.commit(
                        anchor: committed.center,
                        targetZoom: targetZoom,
                        timestamp: event.timestamp,
                        sourceFocus: cameraFocus,
                        sourceZoom: zoom,
                        transitionDuration: shotTransitionDuration
                    )
                    candidate = nil
                    shotLead = cameraFocus
                }
            }

            if let activeCandidate = candidate,
               (sampleTime - activeCandidate.lastSeenAt) > candidateTimeout(for: clampedStrength) {
                candidate = nil
            }

            if cameraActivated == false {
                keyframes.append(
                    CameraKeyframe(
                        timestamp: sampleTime,
                        focus: .center,
                        zoom: baseZoom,
                        emphasis: .none
                    )
                )
                previousSampleTime = sampleTime
                sampleTime += sampleInterval
                continue
            }

            let composition = shotState.composition(at: sampleTime)
            let idleProgress = idleReturnProgress(
                idleAge: max(sampleTime - lastActivityTime, 0),
                followStrength: clampedStrength
            )

            if shotState.phase.allowsWithinShotLead {
                let pointer = interpolatedPointer(at: sampleTime, from: sorted)
                let leadTarget = desiredLeadTarget(
                    anchor: composition.focus,
                    pointer: targetFocus(for: pointer),
                    phase: shotState.phase,
                    idleProgress: idleProgress,
                    followStrength: clampedStrength
                )
                let leadFilter = SmoothingFilter(
                    alpha: smoothingAlpha(
                        base: baseLeadSmoothingAlpha,
                        idle: idleReturnLeadAlpha(for: clampedStrength),
                        idleProgress: idleProgress
                    )
                )
                shotLead = leadFilter.apply(current: shotLead, target: leadTarget)
                let desiredFocus = desiredCameraFocus(
                    anchor: composition.focus,
                    lead: shotLead,
                    followStrength: clampedStrength
                )
                let cameraFilter = SmoothingFilter(
                    alpha: smoothingAlpha(
                        base: baseCameraSmoothingAlpha,
                        idle: idleReturnCameraAlpha(for: clampedStrength),
                        idleProgress: idleProgress
                    )
                )
                cameraFocus = cameraFilter.apply(current: cameraFocus, target: desiredFocus)

                let desiredZoom = desiredZoom(
                    targetZoom: composition.zoom,
                    anchor: composition.focus,
                    lead: shotLead,
                    phase: shotState.phase,
                    idleProgress: idleProgress,
                    baseZoom: baseZoom,
                    followStrength: clampedStrength
                )
                let activeZoomAlpha = smoothingAlpha(
                    base: baseZoomSmoothingAlpha,
                    idle: idleReturnZoomAlpha(for: clampedStrength),
                    idleProgress: idleProgress
                )
                zoom += (desiredZoom - zoom) * activeZoomAlpha
            } else {
                shotLead = composition.focus
                cameraFocus = composition.focus
                zoom = composition.zoom
            }

            let emphasis: CameraKeyframe.EmphasisKind = eventsInWindow.contains(where: { $0.type == .click }) ? .click : .none
            keyframes.append(
                CameraKeyframe(
                    timestamp: sampleTime,
                    focus: cameraFocus,
                    zoom: zoom.clamped(to: 1.0...1.7),
                    emphasis: emphasis
                )
            )

            shotState.updatePhase(at: sampleTime)
            previousSampleTime = sampleTime
            sampleTime += sampleInterval
        }

        return keyframes
    }

    private func fullViewPlan(
        endTime: TimeInterval,
        sampleInterval: TimeInterval,
        baseZoom: Double
    ) -> [CameraKeyframe] {
        var keyframes: [CameraKeyframe] = []
        var sampleTime = 0.0
        while sampleTime <= endTime + 0.0001 {
            keyframes.append(CameraKeyframe(timestamp: sampleTime, focus: .center, zoom: baseZoom, emphasis: .none))
            sampleTime += sampleInterval
        }
        return keyframes.isEmpty ? [CameraKeyframe(timestamp: 0, focus: .center, zoom: baseZoom)] : keyframes
    }

    private func updateCandidate(
        with event: PointerEvent,
        point: NormalizedPoint,
        currentAnchor: NormalizedPoint,
        candidate: CandidateRegion?,
        followStrength: Double
    ) -> CandidateRegion? {
        let distanceFromAnchor = distance(from: currentAnchor, to: point)
        let sameRegionRadius = sameRegionRadius(for: followStrength)
        guard distanceFromAnchor > sameRegionRadius else {
            return nil
        }

        let weight = attentionWeight(for: event.type)
        let isClick = event.type == .click
        let mergeRadius = candidateMergeRadius(for: followStrength)

        if var candidate, distance(from: candidate.center, to: point) <= mergeRadius {
            candidate.absorb(point: point, weight: weight, isClick: isClick, timestamp: event.timestamp)
            return candidate
        }

        return CandidateRegion(
            center: point,
            accumulatedWeight: weight,
            firstSeenAt: event.timestamp,
            lastSeenAt: event.timestamp,
            clickCount: isClick ? 1 : 0
        )
    }

    private func committedCandidate(
        _ candidate: CandidateRegion?,
        currentAnchor: NormalizedPoint,
        currentTime: TimeInterval,
        shotState: ShotState,
        minimumHold: TimeInterval,
        followStrength: Double
    ) -> CandidateRegion? {
        guard let candidate else { return nil }

        let distanceFromAnchor = distance(from: currentAnchor, to: candidate.center)
        guard distanceFromAnchor >= transitionDistance(for: followStrength) else {
            return nil
        }

        guard shotState.canCommit(at: currentTime, minimumHold: minimumHold) else {
            return nil
        }

        if candidate.clickCount > 0 {
            let clickConfidence = 0.82 + (Double(candidate.clickCount) * 0.22)
            if candidate.accumulatedWeight >= clickConfidence || candidate.dwellDuration >= 0.08 {
                return candidate
            }
        }

        if candidate.dwellDuration >= moveDwellDuration(for: followStrength),
           candidate.accumulatedWeight >= moveCommitWeight(for: followStrength) {
            return candidate
        }

        return nil
    }

    private func desiredLeadTarget(
        anchor: NormalizedPoint,
        pointer: NormalizedPoint,
        phase: ShotPhase,
        idleProgress: Double,
        followStrength: Double
    ) -> NormalizedPoint {
        guard phase.allowsWithinShotLead else {
            return anchor
        }

        let returnProgress = idleProgress.clamped(to: 0...1)
        guard returnProgress < 0.999 else {
            return anchor
        }

        let distanceToPointer = distance(from: anchor, to: pointer)
        let deadZone = withinShotDeadZone(for: followStrength)
        guard distanceToPointer > deadZone else {
            return anchor
        }

        let normalizedDistance = ((distanceToPointer - deadZone) / max(1 - deadZone, 0.001)).clamped(to: 0...1)
        let leadWeight = (0.05 + (followStrength * 0.04) + (normalizedDistance * 0.05)).clamped(to: 0.05...0.11)
        let unclampedLead = anchor.blended(toward: pointer, alpha: leadWeight)
        let activeLead = anchor.limitedToward(unclampedLead, maxDistance: maxLeadDistance(for: followStrength))
        return activeLead.blended(toward: anchor, alpha: returnProgress)
    }

    private func desiredCameraFocus(
        anchor: NormalizedPoint,
        lead: NormalizedPoint,
        followStrength: Double
    ) -> NormalizedPoint {
        let leadDistance = distance(from: anchor, to: lead)
        guard leadDistance > 0.0001 else {
            return anchor
        }

        let influence = (0.65 + (followStrength * 0.08)).clamped(to: 0.65...0.75)
        return anchor.blended(toward: lead, alpha: influence)
    }

    private func desiredZoom(
        targetZoom: Double,
        anchor: NormalizedPoint,
        lead: NormalizedPoint,
        phase: ShotPhase,
        idleProgress: Double,
        baseZoom: Double,
        followStrength: Double
    ) -> Double {
        guard phase.allowsWithinShotLead else {
            return targetZoom
        }

        let leadDistance = distance(from: anchor, to: lead)
        let leadBreathing = leadDistance * withinShotZoomLeadMultiplier(for: followStrength)
        let activeZoom = targetZoom + leadBreathing
        let returnProgress = idleProgress.clamped(to: 0...1)
        let idleZoom = targetZoom - ((targetZoom - baseZoom) * idleZoomRelaxation(for: followStrength) * returnProgress)
        return activeZoom + ((idleZoom - activeZoom) * returnProgress)
    }

    private func idleReturnProgress(idleAge: TimeInterval, followStrength: Double) -> Double {
        let delay = idleReturnDelay(for: followStrength)
        let duration = idleReturnDuration(for: followStrength)
        let progress = ((idleAge - delay) / max(duration, 0.0001)).clamped(to: 0...1)
        return progress * progress * (3 - (2 * progress))
    }

    private func smoothingAlpha(base: Double, idle: Double, idleProgress: Double) -> Double {
        base + ((idle - base) * idleProgress.clamped(to: 0...1))
    }

    private func interpolatedPointer(at timestamp: TimeInterval, from events: [PointerEvent]) -> NormalizedPoint {
        guard let first = events.first else { return .center }

        if timestamp <= first.timestamp {
            return first.location
        }

        guard let last = events.last else {
            return first.location
        }

        if timestamp >= last.timestamp {
            return last.location
        }

        guard let upperIndex = events.firstIndex(where: { $0.timestamp >= timestamp }), upperIndex > 0 else {
            return last.location
        }

        let lower = events[upperIndex - 1]
        let upper = events[upperIndex]
        let span = max(upper.timestamp - lower.timestamp, 0.0001)
        let progress = ((timestamp - lower.timestamp) / span).clamped(to: 0...1)
        return NormalizedPoint(
            x: lower.location.x + ((upper.location.x - lower.location.x) * progress),
            y: lower.location.y + ((upper.location.y - lower.location.y) * progress)
        )
    }

    private func shotTargetZoom(
        baseZoom: Double,
        transitionDistance distance: Double,
        followStrength: Double,
        clickRule: ClickEmphasisRule
    ) -> Double {
        let stableShotZoom = baseZoom + stableShotZoomLift(
            for: followStrength,
            zoomLevel: clickRule.boost
        )
        guard distance > 0.0001 else {
            return stableShotZoom.clamped(to: baseZoom...max(baseZoom, 1.72))
        }

        let normalizedDistance = ((distance - transitionDistance(for: followStrength)) / 0.52).clamped(to: 0...1)
        let maximumDistanceLift = 0.025 + (clickRule.boost.clamped(to: 0...1) * 0.26)
        let distanceLift = normalizedDistance * maximumDistanceLift
        return (stableShotZoom + distanceLift).clamped(to: baseZoom...max(baseZoom, 1.95))
    }

    private func attentionWeight(for type: PointerEventType) -> Double {
        switch type {
        case .move:
            0.32
        case .scroll:
            0.5
        case .click:
            1.1
        }
    }

    private func samplingInterval(for followStrength: Double) -> TimeInterval {
        let fps = 18 + Int((followStrength.clamped(to: 0.2...1.0) - 0.2) * 10)
        return 1.0 / Double(fps)
    }

    private func cameraSmoothingAlpha(for followStrength: Double) -> Double {
        (0.11 + (followStrength * 0.07)).clamped(to: 0.11...0.18)
    }

    private func withinShotLeadAlpha(for followStrength: Double) -> Double {
        (0.06 + (followStrength * 0.03)).clamped(to: 0.06...0.09)
    }

    private func zoomSmoothingAlpha(for followStrength: Double) -> Double {
        (0.11 + (followStrength * 0.035)).clamped(to: 0.11...0.16)
    }

    private func idleReturnDelay(for followStrength: Double) -> TimeInterval {
        (0.58 - (followStrength * 0.10)).clamped(to: 0.44...0.58)
    }

    private func idleReturnDuration(for followStrength: Double) -> TimeInterval {
        (0.78 - (followStrength * 0.10)).clamped(to: 0.62...0.78)
    }

    private func idleReturnTailDuration(for followStrength: Double) -> TimeInterval {
        idleReturnDelay(for: followStrength) + idleReturnDuration(for: followStrength) + 0.65
    }

    private func idleZoomRelaxation(for followStrength: Double) -> Double {
        (0.46 + (followStrength * 0.14)).clamped(to: 0.48...0.60)
    }

    private func idleReturnLeadAlpha(for followStrength: Double) -> Double {
        (0.18 + (followStrength * 0.05)).clamped(to: 0.18...0.23)
    }

    private func idleReturnCameraAlpha(for followStrength: Double) -> Double {
        (0.16 + (followStrength * 0.05)).clamped(to: 0.16...0.21)
    }

    private func idleReturnZoomAlpha(for followStrength: Double) -> Double {
        (0.15 + (followStrength * 0.04)).clamped(to: 0.15...0.19)
    }

    private func stableShotZoomLift(for followStrength: Double, zoomLevel: Double) -> Double {
        let motionLift = (0.008 + (followStrength * 0.018)).clamped(to: 0.014...0.032)
        let zoomLift = zoomLevel.clamped(to: 0...1) * 0.48
        return (motionLift + zoomLift).clamped(to: 0.014...0.58)
    }

    private func withinShotZoomLeadMultiplier(for followStrength: Double) -> Double {
        (0.026 + (followStrength * 0.018)).clamped(to: 0.026...0.044)
    }

    private func sameRegionRadius(for followStrength: Double) -> Double {
        (0.13 - (followStrength * 0.02)).clamped(to: 0.10...0.13)
    }

    private func candidateMergeRadius(for followStrength: Double) -> Double {
        (0.16 - (followStrength * 0.03)).clamped(to: 0.12...0.16)
    }

    private func transitionDistance(for followStrength: Double) -> Double {
        (0.22 - (followStrength * 0.03)).clamped(to: 0.18...0.22)
    }

    private func shotTransitionDuration(for followStrength: Double) -> TimeInterval {
        (0.34 - (followStrength * 0.05)).clamped(to: 0.26...0.34)
    }

    private func minimumShotHold(for followStrength: Double) -> TimeInterval {
        (0.44 - (followStrength * 0.08)).clamped(to: 0.28...0.44)
    }

    private func moveDwellDuration(for followStrength: Double) -> TimeInterval {
        (0.26 - (followStrength * 0.05)).clamped(to: 0.18...0.26)
    }

    private func moveCommitWeight(for followStrength: Double) -> Double {
        (1.22 - (followStrength * 0.16)).clamped(to: 0.95...1.22)
    }

    private func candidateTimeout(for followStrength: Double) -> TimeInterval {
        (0.34 - (followStrength * 0.06)).clamped(to: 0.22...0.34)
    }

    private func withinShotDeadZone(for followStrength: Double) -> Double {
        (0.082 - (followStrength * 0.014)).clamped(to: 0.06...0.082)
    }

    private func maxLeadDistance(for followStrength: Double) -> Double {
        (0.044 + (followStrength * 0.012)).clamped(to: 0.044...0.056)
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

    private func distance(from lhs: NormalizedPoint, to rhs: NormalizedPoint) -> Double {
        let dx = rhs.x - lhs.x
        let dy = rhs.y - lhs.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

private extension NormalizedPoint {
    func blended(toward target: NormalizedPoint, alpha: Double) -> NormalizedPoint {
        NormalizedPoint(
            x: x + ((target.x - x) * alpha),
            y: y + ((target.y - y) * alpha)
        )
    }

    func limitedToward(_ target: NormalizedPoint, maxDistance: Double) -> NormalizedPoint {
        let dx = target.x - x
        let dy = target.y - y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > maxDistance, distance > 0.0001 else {
            return target
        }

        let ratio = maxDistance / distance
        return NormalizedPoint(
            x: x + (dx * ratio),
            y: y + (dy * ratio)
        )
    }
}
