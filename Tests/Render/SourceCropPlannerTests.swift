import CoreGraphics
import XCTest
@testable import MouseLens

final class SourceCropPlannerTests: XCTestCase {
    func testBaseCropKeepsRequestedAspectRatioCentered() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let crop = planner.baseCropRect(for: source, outputAspectRatio: 9.0 / 16.0)

        XCTAssertEqual(crop.width / crop.height, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(crop.midX, source.midX, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, source.midY, accuracy: 0.0001)
    }

    func testFocusedCropStaysInsideSourceBounds() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshot = FrameSnapshot(
            focus: .init(x: 0.98, y: 0.02),
            zoom: 1.6,
            emphasis: .none
        )

        let crop = planner.cropRect(
            for: source,
            outputAspectRatio: 16.0 / 9.0,
            snapshot: snapshot
        )

        XCTAssertGreaterThanOrEqual(crop.minX, source.minX)
        XCTAssertGreaterThanOrEqual(crop.minY, source.minY)
        XCTAssertLessThanOrEqual(crop.maxX, source.maxX)
        XCTAssertLessThanOrEqual(crop.maxY, source.maxY)
        XCTAssertLessThan(crop.width, source.width)
        XCTAssertLessThan(crop.height, source.height)
    }

    func testFocusedCropCentersOnRequestedPointWhenNotNearAnEdge() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshot = FrameSnapshot(
            focus: .init(x: 0.50, y: 0.50),
            zoom: 1.25,
            emphasis: .click
        )

        let crop = planner.cropRect(
            for: source,
            outputAspectRatio: 16.0 / 9.0,
            snapshot: snapshot
        )

        let expectedX = source.minX + (snapshot.focus.x * source.width)
        let expectedY = source.maxY - (snapshot.focus.y * source.height)

        XCTAssertEqual(crop.midX, expectedX, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, expectedY, accuracy: 0.0001)
    }

    func testFocusedCropAllowsManualZoomHeadroom() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshot = FrameSnapshot(
            focus: .center,
            zoom: 2.4,
            emphasis: .none
        )

        let crop = planner.cropRect(
            for: source,
            outputAspectRatio: 16.0 / 9.0,
            snapshot: snapshot
        )

        XCTAssertEqual(crop.width, 800, accuracy: 0.0001)
        XCTAssertEqual(crop.height, 450, accuracy: 0.0001)
    }

    func testMappedContentPointMatchesVisualCenterForCenteredCrop() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0.08)
        let snapshot = FrameSnapshot(
            focus: .init(x: 0.50, y: 0.50),
            zoom: 1.35,
            emphasis: .click
        )

        let crop = planner.cropRect(
            for: source,
            outputAspectRatio: layout.outputAspectRatio,
            snapshot: snapshot
        )
        let mappedPoint = planner.mappedContentPoint(
            for: snapshot.focus,
            in: source,
            cropRect: crop,
            layout: layout
        )

        XCTAssertEqual(mappedPoint.x, layout.contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(mappedPoint.y, layout.contentRect.midY, accuracy: 0.0001)
    }

    func testRenderLayoutUsesPaddingToInsetContentRect() {
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0.1)

        XCTAssertEqual(layout.contentRect.minX, 192, accuracy: 0.0001)
        XCTAssertEqual(layout.contentRect.minY, 108, accuracy: 0.0001)
        XCTAssertEqual(layout.contentRect.width, 1536, accuracy: 0.0001)
        XCTAssertEqual(layout.contentRect.height, 864, accuracy: 0.0001)
        XCTAssertEqual(layout.outputAspectRatio, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testRealtimePreviewGeometryMapsCursorIntoPaddedContentRect() {
        let contentRect = CGRect(x: 120, y: 80, width: 1440, height: 810)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 1920, height: 1080),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none)
        )

        let point = geometry.contentPoint(for: .center)

        XCTAssertEqual(point.x, contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(point.y, contentRect.midY, accuracy: 0.0001)
    }

    func testCursorGeometryKeepsTipPinnedToEventPoint() {
        let tip = CGPoint(x: 420, y: 260)
        let scale: CGFloat = 1.35
        let origin = CursorGeometry.origin(forTip: tip, scale: scale)

        XCTAssertEqual((origin.x + CursorGeometry.hotspot.x) * scale, tip.x, accuracy: 0.0001)
        XCTAssertEqual((origin.y + CursorGeometry.hotspot.y) * scale, tip.y, accuracy: 0.0001)
    }

    func testRealtimePreviewGeometryScalesVideoWhenManualZoomIsActive() {
        let contentRect = CGRect(x: 0, y: 0, width: 1440, height: 810)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 1920, height: 1080),
            contentRect: contentRect,
            snapshot: FrameSnapshot(
                focus: .init(x: 0.35, y: 0.42),
                zoom: 2.0,
                emphasis: .none
            )
        )

        XCTAssertGreaterThan(geometry.videoFrame.width, contentRect.width)
        XCTAssertGreaterThan(geometry.videoFrame.height, contentRect.height)
    }
}

final class FrameComposerManualZoomTests: XCTestCase {
    func testManualZoomOverridesAutoSnapshotInsideSegment() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 2, focus: .center, zoom: 1.2)
        ]
        let segment = ManualZoomSegment(
            start: 0.5,
            end: 1.5,
            focus: .init(x: 0.8, y: 0.2),
            zoomLevel: 2.2,
            easeInDuration: 0.1,
            easeOutDuration: 0.1
        )

        let snapshot = composer.snapshot(at: 1.0, from: keyframes, manualZoomSegments: [segment])

        XCTAssertEqual(snapshot.focus.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.focus.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.zoom, 2.2, accuracy: 0.0001)
    }

    func testManualZoomWinsOverOverlappingAutoZoom() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 2, focus: .center, zoom: 1.2)
        ]
        let auto = ManualZoomSegment(
            start: 0.5,
            end: 1.5,
            focus: .init(x: 0.2, y: 0.2),
            zoomLevel: 1.5,
            easeInDuration: 0,
            easeOutDuration: 0,
            source: .auto
        )
        let manual = ManualZoomSegment(
            start: 0.8,
            end: 1.2,
            focus: .init(x: 0.8, y: 0.3),
            zoomLevel: 2.2,
            easeInDuration: 0,
            easeOutDuration: 0,
            source: .manual
        )

        let snapshot = composer.snapshot(at: 1.0, from: keyframes, manualZoomSegments: [auto, manual])

        XCTAssertEqual(snapshot.focus.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.focus.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(snapshot.zoom, 2.2, accuracy: 0.0001)
    }

    func testAutoZoomSegmentDoesNotDoubleApplyCameraPlan() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 1, focus: .init(x: 0.7, y: 0.3), zoom: 1.6)
        ]
        let auto = ManualZoomSegment(
            start: 0.5,
            end: 1.5,
            focus: .init(x: 0.1, y: 0.9),
            zoomLevel: 2.2,
            easeInDuration: 0,
            easeOutDuration: 0,
            source: .auto
        )

        let baseSnapshot = composer.snapshot(at: 1.0, from: keyframes)
        let trackedSnapshot = composer.snapshot(at: 1.0, from: keyframes, manualZoomSegments: [auto])

        XCTAssertEqual(trackedSnapshot, baseSnapshot)
    }

    func testManualZoomEasesAtSegmentBoundaries() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 2, focus: .center, zoom: 1.0)
        ]
        let segment = ManualZoomSegment(
            start: 0.5,
            end: 1.5,
            focus: .init(x: 0.8, y: 0.2),
            zoomLevel: 2.0,
            easeInDuration: 0.4,
            easeOutDuration: 0.4
        )

        let startSnapshot = composer.snapshot(at: 0.5, from: keyframes, manualZoomSegments: [segment])
        let easingSnapshot = composer.snapshot(at: 0.7, from: keyframes, manualZoomSegments: [segment])
        let fullSnapshot = composer.snapshot(at: 1.0, from: keyframes, manualZoomSegments: [segment])

        XCTAssertEqual(startSnapshot.zoom, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(easingSnapshot.zoom, 1.0)
        XCTAssertLessThan(easingSnapshot.zoom, 2.0)
        XCTAssertEqual(fullSnapshot.zoom, 2.0, accuracy: 0.0001)
    }
}

final class PointerTimelineTests: XCTestCase {
    func testPointerTimelineSmoothsMovePathWithoutChangingRawLocation() throws {
        let timeline = PointerTimeline()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.20, y: 0.50), type: .move),
            PointerEvent(timestamp: 0.10, location: .init(x: 0.80, y: 0.50), type: .move),
            PointerEvent(timestamp: 0.20, location: .init(x: 0.20, y: 0.50), type: .move)
        ]

        let snapshot = try XCTUnwrap(timeline.snapshot(at: 0.10, from: events))

        XCTAssertEqual(snapshot.rawLocation.x, 0.80, accuracy: 0.0001)
        XCTAssertLessThan(snapshot.location.x, snapshot.rawLocation.x)
        XCTAssertGreaterThan(snapshot.location.x, 0.70)
    }

    func testPointerTimelineRawModeDoesNotSmoothVisibleCursor() throws {
        let timeline = PointerTimeline()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.20, y: 0.50), type: .move),
            PointerEvent(timestamp: 0.10, location: .init(x: 0.80, y: 0.50), type: .move),
            PointerEvent(timestamp: 0.20, location: .init(x: 0.20, y: 0.50), type: .move)
        ]

        let snapshot = try XCTUnwrap(timeline.snapshot(at: 0.10, from: events, smoothing: .raw))

        XCTAssertEqual(snapshot.rawLocation.x, 0.80, accuracy: 0.0001)
        XCTAssertEqual(snapshot.location.x, snapshot.rawLocation.x, accuracy: 0.0001)
    }

    func testPointerTimelineKeepsClickRipplePinnedWhileCursorMovesAway() throws {
        let timeline = PointerTimeline()
        let events = [
            PointerEvent(timestamp: 0.0, location: .init(x: 0.20, y: 0.40), type: .move),
            PointerEvent(timestamp: 0.20, location: .init(x: 0.80, y: 0.40), type: .click),
            PointerEvent(timestamp: 0.30, location: .init(x: 0.20, y: 0.40), type: .move)
        ]

        let click = try XCTUnwrap(timeline.snapshot(at: 0.20, from: events))
        let afterClick = try XCTUnwrap(timeline.snapshot(at: 0.28, from: events))
        let expired = try XCTUnwrap(timeline.snapshot(at: 0.60, from: events))
        let clickLocation = try XCTUnwrap(afterClick.clickLocation)

        XCTAssertEqual(click.location.x, 0.80, accuracy: 0.0001)
        XCTAssertEqual(clickLocation.x, 0.80, accuracy: 0.0001)
        XCTAssertLessThan(afterClick.location.x, 0.55)
        XCTAssertGreaterThan(afterClick.clickProgress, 0.5)
        XCTAssertNil(expired.clickLocation)
        XCTAssertEqual(expired.clickProgress, 0, accuracy: 0.0001)
    }
}
