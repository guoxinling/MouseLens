import XCTest
@testable import MouseLens

final class CameraPlanEngineTests: XCTestCase {
    func testClickBoostRaisesZoomImmediatelyAfterClick() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.2, y: 0.2), type: .move),
            PointerEvent(timestamp: 0.5, location: .init(x: 0.5, y: 0.5), type: .click),
            PointerEvent(timestamp: 0.6, location: .init(x: 0.55, y: 0.52), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.5,
            clickRule: ClickEmphasisRule(boost: 0.4, duration: 0.5)
        )

        XCTAssertEqual(plan.count, 3)
        XCTAssertGreaterThan(plan[1].zoom, plan[0].zoom)
        XCTAssertGreaterThan(plan[2].zoom, 1.0)
    }

    func testSmoothingMovesFocusTowardTargetWithoutJumpingFully() {
        let engine = CameraPlanEngine()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.1, y: 0.1), type: .move),
            PointerEvent(timestamp: 1.0, location: .init(x: 0.9, y: 0.9), type: .move)
        ]

        let plan = engine.makePlan(
            from: events,
            baseZoom: 1.0,
            followStrength: 0.25,
            clickRule: ClickEmphasisRule(boost: 0.0, duration: 0.3)
        )

        XCTAssertLessThan(plan[1].focus.x, 0.9)
        XCTAssertLessThan(plan[1].focus.y, 0.9)
        XCTAssertGreaterThan(plan[1].focus.x, 0.1)
    }
}
