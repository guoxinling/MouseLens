import XCTest
@testable import MouseLens

final class CameraPlanEngineTests: XCTestCase {
    func testCameraPlanKeepsFullViewUntilFirstClick() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.20, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.45, location: .init(x: 0.70, y: 0.42), type: .move),
            PointerEvent(timestamp: 1.00, location: .init(x: 0.82, y: 0.46), type: .click)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let openingFrames = plan.filter { $0.timestamp < 0.40 }
        XCTAssertFalse(openingFrames.isEmpty)
        XCTAssertTrue(openingFrames.allSatisfy { abs($0.zoom - 1.0) < 0.0001 })
        XCTAssertTrue(openingFrames.allSatisfy { abs($0.focus.x - 0.5) < 0.0001 && abs($0.focus.y - 0.5) < 0.0001 })

        let anticipated = snapshot(in: plan, nearestTo: 0.50)
        XCTAssertGreaterThan(anticipated.focus.x, 0.5)
        XCTAssertEqual(anticipated.zoom, 1.0, accuracy: 0.0001)

        let clickTime = snapshot(in: plan, nearestTo: 1.00)
        XCTAssertEqual(clickTime.focus.x, 0.82, accuracy: 0.025)
        XCTAssertEqual(clickTime.focus.y, 0.46, accuracy: 0.025)

        let afterClick = snapshot(in: plan, nearestTo: 1.35)
        XCTAssertGreaterThan(afterClick.zoom, 1.03)
        XCTAssertGreaterThan(afterClick.focus.x, 0.5)

        let sampleInterval = (plan[1].timestamp - plan[0].timestamp)
        XCTAssertEqual(sampleInterval, 1.0 / 60.0, accuracy: 0.0001)
    }

    func testCameraFocusUsesActualClickPointNearEdges() {
        let engine = CameraPlanEngine()
        let clickPoint = NormalizedPoint(x: 0.03, y: 0.94)
        let events = [
            PointerEvent(timestamp: 0.2, location: clickPoint, type: .click)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let settled = snapshot(in: plan, nearestTo: 0.85)
        XCTAssertEqual(settled.focus.x, clickPoint.x, accuracy: 0.0001)
        XCTAssertEqual(settled.focus.y, clickPoint.y, accuracy: 0.0001)
    }

    func testCameraPlanWithoutClicksStaysFullView() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.22, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.30, location: .init(x: 0.72, y: 0.45), type: .move),
            PointerEvent(timestamp: 0.70, location: .init(x: 0.78, y: 0.46), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { abs($0.zoom - 1.0) < 0.0001 })
        XCTAssertTrue(plan.allSatisfy { abs($0.focus.x - 0.5) < 0.0001 && abs($0.focus.y - 0.5) < 0.0001 })
    }

    func testNearbyClicksStayInsideSameShotWithoutZoomPumping() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.50, y: 0.46), type: .move),
            PointerEvent(timestamp: 0.05, location: .init(x: 0.56, y: 0.48), type: .click),
            PointerEvent(timestamp: 0.80, location: .init(x: 0.58, y: 0.49), type: .click),
            PointerEvent(timestamp: 0.91, location: .init(x: 0.60, y: 0.50), type: .click)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let firstClick = snapshot(in: plan, nearestTo: 0.70)
        let secondClick = snapshot(in: plan, nearestTo: 0.80)
        let thirdClick = snapshot(in: plan, nearestTo: 0.91)

        XCTAssertLessThan(abs(secondClick.zoom - firstClick.zoom), 0.025)
        XCTAssertLessThan(abs(thirdClick.zoom - secondClick.zoom), 0.025)
        XCTAssertLessThan(abs(thirdClick.focus.x - firstClick.focus.x), 0.08)
        XCTAssertLessThan(abs(thirdClick.focus.y - firstClick.focus.y), 0.08)
    }

    func testModerateDistanceClickReanchorsCameraFocus() {
        let engine = CameraPlanEngine()
        let firstClick = NormalizedPoint(x: 0.24, y: 0.67)
        let secondClick = NormalizedPoint(x: 0.27, y: 0.79)
        let events = [
            PointerEvent(timestamp: 0.05, location: firstClick, type: .click),
            PointerEvent(timestamp: 0.80, location: secondClick, type: .click)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let settled = snapshot(in: plan, nearestTo: 1.45)

        XCTAssertEqual(settled.focus.x, secondClick.x, accuracy: 0.015)
        XCTAssertEqual(settled.focus.y, secondClick.y, accuracy: 0.015)
    }

    func testFarClickStartsNewShotWithGentleCameraTravel() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.24, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.55, location: .init(x: 0.82, y: 0.46), type: .click)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let beforeTransition = snapshot(in: plan, nearestTo: 0.48)
        let transition = snapshot(in: plan, nearestTo: 0.55)
        let settled = snapshot(in: plan, nearestTo: 0.90)

        XCTAssertGreaterThan(transition.focus.x, beforeTransition.focus.x)
        XCTAssertLessThan(transition.focus.x, 0.82)
        XCTAssertGreaterThan(settled.focus.x, transition.focus.x)
        XCTAssertGreaterThan(transition.zoom, beforeTransition.zoom)
        XCTAssertGreaterThan(settled.zoom, 1.03)
    }

    func testCommittedShotZoomPersistsInsteadOfDecayingBackOut() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.24, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.55, location: .init(x: 0.82, y: 0.46), type: .click),
            PointerEvent(timestamp: 1.45, location: .init(x: 0.84, y: 0.47), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let transitionPeak = plan
            .filter { $0.timestamp >= 0.95 && $0.timestamp <= 1.15 }
            .map(\.zoom)
            .max() ?? 1.0
        let held = snapshot(in: plan, nearestTo: 1.75)

        XCTAssertGreaterThan(transitionPeak, 1.08)
        XCTAssertGreaterThanOrEqual(held.zoom, transitionPeak - 0.02)
    }

    func testMaximumMotionZoomProducesStrongerCameraPush() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.20, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.60, location: .init(x: 0.84, y: 0.48), type: .click)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.82,
            clickRule: ClickEmphasisRule(boost: 1.0, duration: 0.72)
        )

        let peakZoom = plan.map(\.zoom).max() ?? 1.0
        XCTAssertGreaterThan(peakZoom, 1.50)
    }

    func testRapidFarClickDuringTransitionDoesNotStealShot() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.24, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.55, location: .init(x: 0.82, y: 0.46), type: .click),
            PointerEvent(timestamp: 0.66, location: .init(x: 0.26, y: 0.30), type: .click),
            PointerEvent(timestamp: 1.10, location: .init(x: 0.84, y: 0.47), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let held = snapshot(in: plan, nearestTo: 1.05)

        XCTAssertGreaterThan(held.focus.x, 0.75)
    }

    func testSustainedMovementWithoutClickDoesNotCreateZoomShot() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.22, y: 0.28), type: .move),
            PointerEvent(timestamp: 0.20, location: .init(x: 0.68, y: 0.44), type: .move),
            PointerEvent(timestamp: 0.34, location: .init(x: 0.72, y: 0.45), type: .move),
            PointerEvent(timestamp: 0.50, location: .init(x: 0.75, y: 0.46), type: .move),
            PointerEvent(timestamp: 0.68, location: .init(x: 0.77, y: 0.46), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let start = snapshot(in: plan, nearestTo: 0.05)
        let afterDwell = snapshot(in: plan, nearestTo: 1.02)

        XCTAssertEqual(start.focus.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(afterDwell.focus.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(afterDwell.zoom, 1.0, accuracy: 0.0001)
    }

    func testShotTransitionAnticipatesClickAndSettlesWithoutOvershoot() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.24, y: 0.28), type: .move),
            PointerEvent(timestamp: 1.00, location: .init(x: 0.82, y: 0.46), type: .click),
            PointerEvent(timestamp: 1.45, location: .init(x: 0.82, y: 0.46), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let beforeAnticipation = snapshot(in: plan, nearestTo: 0.38)
        let anticipated = snapshot(in: plan, nearestTo: 0.52)
        let clickTime = snapshot(in: plan, nearestTo: 1.00)
        let settled = snapshot(in: plan, nearestTo: 1.32)
        let maximumTransitionX = plan
            .filter { $0.timestamp >= 0.42 && $0.timestamp <= 1.20 }
            .map(\.focus.x)
            .max() ?? 0

        XCTAssertEqual(beforeAnticipation.focus.x, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(anticipated.focus.x, beforeAnticipation.focus.x)
        XCTAssertEqual(clickTime.focus.x, 0.82, accuracy: 0.025)
        XCTAssertEqual(clickTime.focus.y, 0.46, accuracy: 0.025)
        XCTAssertGreaterThan(settled.zoom, clickTime.zoom)
        XCTAssertLessThanOrEqual(maximumTransitionX, 0.83)
    }

    func testWithinShotPointerMovementDoesNotDragCameraAwayFromClickAnchor() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.05, location: .init(x: 0.44, y: 0.45), type: .click),
            PointerEvent(timestamp: 0.0, location: .init(x: 0.44, y: 0.45), type: .move),
            PointerEvent(timestamp: 0.25, location: .init(x: 0.50, y: 0.47), type: .move),
            PointerEvent(timestamp: 0.50, location: .init(x: 0.57, y: 0.48), type: .move),
            PointerEvent(timestamp: 0.75, location: .init(x: 0.62, y: 0.50), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let later = snapshot(in: plan, nearestTo: 0.80)

        XCTAssertEqual(later.focus.x, 0.44, accuracy: 0.0001)
        XCTAssertEqual(later.focus.y, 0.45, accuracy: 0.0001)
        XCTAssertGreaterThan(later.zoom, 1.0)
    }

    func testIdleReturnRecentersShotAfterClickInactivity() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.05, location: .init(x: 0.44, y: 0.45), type: .click),
            PointerEvent(timestamp: 0.0, location: .init(x: 0.44, y: 0.45), type: .move),
            PointerEvent(timestamp: 0.25, location: .init(x: 0.50, y: 0.47), type: .move),
            PointerEvent(timestamp: 0.50, location: .init(x: 0.56, y: 0.48), type: .move),
            PointerEvent(timestamp: 0.75, location: .init(x: 0.60, y: 0.50), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.72,
            clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
        )

        let anchor = NormalizedPoint(x: 0.44, y: 0.45)
        let activeShot = snapshot(in: plan, nearestTo: 0.85)
        let returned = snapshot(in: plan, nearestTo: 3.20)

        XCTAssertEqual(activeShot.focus.x, anchor.x, accuracy: 0.0001)
        XCTAssertEqual(activeShot.focus.y, anchor.y, accuracy: 0.0001)
        XCTAssertGreaterThan(activeShot.zoom, 1.0)
        XCTAssertLessThan(abs(returned.focus.x - 0.5), abs(activeShot.focus.x - 0.5))
        XCTAssertLessThan(abs(returned.focus.y - 0.5), abs(activeShot.focus.y - 0.5))
        XCTAssertLessThan(returned.zoom, activeShot.zoom)
        XCTAssertEqual(returned.zoom, 1.0, accuracy: 0.0001)
    }

    private func snapshot(in plan: [CameraKeyframe], nearestTo timestamp: TimeInterval) -> CameraKeyframe {
        guard let keyframe = plan.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }) else {
            XCTFail("Expected camera plan to contain keyframes.")
            return CameraKeyframe(timestamp: timestamp, focus: .center, zoom: 1.0)
        }
        return keyframe
    }
}
