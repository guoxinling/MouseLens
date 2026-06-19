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
        var zoomDelay: TimeInterval

        func focus(at timestamp: TimeInterval) -> NormalizedPoint {
            sourceFocus.blended(toward: targetFocus, alpha: easedProgress(at: timestamp))
        }

        func zoom(at timestamp: TimeInterval) -> Double {
            let progress = easedZoomProgress(at: timestamp)
            return sourceZoom + ((targetZoom - sourceZoom) * progress)
        }

        func isComplete(at timestamp: TimeInterval) -> Bool {
            progress(at: timestamp) >= 1 && zoomProgress(at: timestamp) >= 1
        }

        private func easedProgress(at timestamp: TimeInterval) -> Double {
            let t = progress(at: timestamp)
            return t * t * t * (t * ((t * 6) - 15) + 10)
        }

        private func easedZoomProgress(at timestamp: TimeInterval) -> Double {
            let t = zoomProgress(at: timestamp)
            return t * t * t * (t * ((t * 6) - 15) + 10)
        }

        private func progress(at timestamp: TimeInterval) -> Double {
            ((timestamp - startedAt) / max(duration, 0.0001)).clamped(to: 0...1)
        }

        private func zoomProgress(at timestamp: TimeInterval) -> Double {
            ((timestamp - startedAt - zoomDelay) / max(duration, 0.0001)).clamped(to: 0...1)
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
            transitionDuration: TimeInterval,
            zoomDelay: TimeInterval
        ) {
            shot = Shot(anchor: anchor, targetZoom: targetZoom, startedAt: timestamp)
            transition = ShotTransition(
                sourceFocus: sourceFocus,
                sourceZoom: sourceZoom,
                targetFocus: anchor,
                targetZoom: targetZoom,
                startedAt: timestamp,
                duration: transitionDuration,
                zoomDelay: zoomDelay
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

        func canCommitClick(at timestamp: TimeInterval, minimumHold: TimeInterval) -> Bool {
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
        let focusAnticipation = focusAnticipation(transitionDuration: shotTransitionDuration)
        let minimumShotHold = minimumShotHold(for: clampedStrength)
        var cameraFocus = NormalizedPoint.center
        var zoom = baseZoom
        var candidate: CandidateRegion?
        var cameraActivated = false
        var keyframes: [CameraKeyframe] = []
        var previousSampleTime = -0.0001
        var sampleTime = 0.0
        var lastActivityTime = firstClick.timestamp
        var nextEventIndex = 0

        while sampleTime <= endTime + 0.0001 {
            var eventsInWindow: [PointerEvent] = []
            while nextEventIndex < sorted.count,
                  sorted[nextEventIndex].timestamp <= sampleTime + focusAnticipation {
                eventsInWindow.append(sorted[nextEventIndex])
                nextEventIndex += 1
            }
            let visibleEventsInWindow = sorted.filter {
                $0.timestamp > previousSampleTime && $0.timestamp <= sampleTime
            }

            for event in eventsInWindow {
                guard event.timestamp >= firstClick.timestamp else { continue }
                guard event.type != .move else { continue }
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
                    let transitionStart = max(event.timestamp - focusAnticipation, 0)
                    shotState.commit(
                        anchor: eventPoint,
                        targetZoom: targetZoom,
                        timestamp: transitionStart,
                        sourceFocus: .center,
                        sourceZoom: baseZoom,
                        transitionDuration: shotTransitionDuration,
                        zoomDelay: zoomTransitionDelay(
                            eventTimestamp: event.timestamp,
                            transitionStart: transitionStart,
                            transitionDuration: shotTransitionDuration
                        )
                    )
                    cameraActivated = true
                    candidate = nil
                    continue
                }

                guard cameraActivated else { continue }
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
                    let transitionStart = max(event.timestamp - focusAnticipation, 0)
                    shotState.commit(
                        anchor: committed.center,
                        targetZoom: targetZoom,
                        timestamp: transitionStart,
                        sourceFocus: cameraFocus,
                        sourceZoom: zoom,
                        transitionDuration: shotTransitionDuration,
                        zoomDelay: zoomTransitionDelay(
                            eventTimestamp: event.timestamp,
                            transitionStart: transitionStart,
                            transitionDuration: shotTransitionDuration
                        )
                    )
                    candidate = nil
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

            cameraFocus = composition.focus.blended(toward: .center, alpha: idleProgress)
            zoom = composition.zoom + ((baseZoom - composition.zoom) * idleProgress)

            let emphasis: CameraKeyframe.EmphasisKind = visibleEventsInWindow.contains(where: { $0.type == .click }) ? .click : .none
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
        let sameRegionRadius = event.type == .click
            ? clickSameRegionRadius(for: followStrength)
            : sameRegionRadius(for: followStrength)
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
        let requiredDistance = candidate.clickCount > 0
            ? clickTransitionDistance(for: followStrength)
            : transitionDistance(for: followStrength)
        guard distanceFromAnchor >= requiredDistance else {
            return nil
        }

        if candidate.clickCount > 0 {
            guard shotState.canCommitClick(
                at: currentTime,
                minimumHold: clickMinimumShotHold(for: followStrength)
            ) else { return nil }
            return candidate
        }

        guard shotState.canCommit(at: currentTime, minimumHold: minimumHold) else {
            return nil
        }

        if candidate.dwellDuration >= moveDwellDuration(for: followStrength),
           candidate.accumulatedWeight >= moveCommitWeight(for: followStrength) {
            return candidate
        }

        return nil
    }

    private func idleReturnProgress(idleAge: TimeInterval, followStrength: Double) -> Double {
        let delay = idleReturnDelay(for: followStrength)
        let duration = idleReturnDuration(for: followStrength)
        let progress = ((idleAge - delay) / max(duration, 0.0001)).clamped(to: 0...1)
        return progress * progress * (3 - (2 * progress))
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
        1.0 / 60.0
    }

    private func focusAnticipation(transitionDuration: TimeInterval) -> TimeInterval {
        transitionDuration
    }

    private func idleReturnDelay(for followStrength: Double) -> TimeInterval {
        1.20
    }

    private func idleReturnDuration(for followStrength: Double) -> TimeInterval {
        0.90
    }

    private func idleReturnTailDuration(for followStrength: Double) -> TimeInterval {
        idleReturnDelay(for: followStrength) + idleReturnDuration(for: followStrength) + 0.80
    }

    private func stableShotZoomLift(for followStrength: Double, zoomLevel: Double) -> Double {
        let motionLift = (0.008 + (followStrength * 0.018)).clamped(to: 0.014...0.032)
        let zoomLift = zoomLevel.clamped(to: 0...1) * 0.48
        return (motionLift + zoomLift).clamped(to: 0.014...0.58)
    }

    private func sameRegionRadius(for followStrength: Double) -> Double {
        (0.13 - (followStrength * 0.02)).clamped(to: 0.10...0.13)
    }

    private func clickSameRegionRadius(for followStrength: Double) -> Double {
        (0.065 - (followStrength * 0.015)).clamped(to: 0.045...0.065)
    }

    private func candidateMergeRadius(for followStrength: Double) -> Double {
        (0.16 - (followStrength * 0.03)).clamped(to: 0.12...0.16)
    }

    private func transitionDistance(for followStrength: Double) -> Double {
        (0.22 - (followStrength * 0.03)).clamped(to: 0.18...0.22)
    }

    private func clickTransitionDistance(for followStrength: Double) -> Double {
        (0.075 - (followStrength * 0.02)).clamped(to: 0.052...0.075)
    }

    private func shotTransitionDuration(for followStrength: Double) -> TimeInterval {
        0.58
    }

    private func zoomTransitionDelay(
        eventTimestamp: TimeInterval,
        transitionStart: TimeInterval,
        transitionDuration: TimeInterval
    ) -> TimeInterval {
        let elapsedBeforeEvent = max(eventTimestamp - transitionStart, 0)
        let zoomLeadAtClick: TimeInterval = 0.12
        return max(elapsedBeforeEvent - zoomLeadAtClick, 0)
    }

    private func minimumShotHold(for followStrength: Double) -> TimeInterval {
        (0.44 - (followStrength * 0.08)).clamped(to: 0.28...0.44)
    }

    private func clickMinimumShotHold(for followStrength: Double) -> TimeInterval {
        (0.18 - (followStrength * 0.06)).clamped(to: 0.10...0.18)
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

    private func targetFocus(for point: NormalizedPoint) -> NormalizedPoint {
        point
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
