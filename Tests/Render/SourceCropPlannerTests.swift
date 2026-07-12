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

    func testFocusedCropCanOverscanToKeepEdgeClickCentered() {
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

        let expectedX = source.minX + (snapshot.focus.x * source.width)
        let expectedY = source.maxY - (snapshot.focus.y * source.height)

        XCTAssertEqual(crop.midX, expectedX, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, expectedY, accuracy: 0.0001)
        XCTAssertGreaterThan(crop.maxX, source.maxX)
        XCTAssertGreaterThan(crop.maxY, source.maxY)
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

    func testMappedContentPointMatchesVisualCenterForEdgeAnchoredCrop() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0.04)
        let snapshot = FrameSnapshot(
            focus: .init(x: 0.08, y: 0.12),
            zoom: 1.55,
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

    func testMappedContentPointUsesTopOriginPointerCoordinates() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0)
        let crop = planner.cropRect(
            for: source,
            outputAspectRatio: layout.outputAspectRatio,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none)
        )

        let topLeft = planner.mappedContentPoint(
            for: NormalizedPoint(x: 0, y: 0),
            in: source,
            cropRect: crop,
            layout: layout
        )
        let bottomRight = planner.mappedContentPoint(
            for: NormalizedPoint(x: 1, y: 1),
            in: source,
            cropRect: crop,
            layout: layout
        )

        XCTAssertEqual(topLeft.x, layout.contentRect.minX, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, layout.contentRect.minY, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.x, layout.contentRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y, layout.contentRect.maxY, accuracy: 0.0001)
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
        XCTAssertEqual(geometry.contentRect.minX, contentRect.minX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentRect.minY, contentRect.minY, accuracy: 0.0001)
        XCTAssertEqual(geometry.videoFrame.midX, contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(geometry.videoFrame.midY, contentRect.midY, accuracy: 0.0001)
    }

    func testRealtimePreviewAndExportUseSamePointMapping() {
        let planner = SourceCropPlanner()
        let contentRect = CGRect(x: 80, y: 60, width: 1600, height: 900)
        let sourceSize = CGSize(width: 2560, height: 1440)
        let snapshot = FrameSnapshot(focus: .init(x: 0.27, y: 0.73), zoom: 1.62, emphasis: .click)
        let point = NormalizedPoint(x: 0.31, y: 0.68)
        let geometry = RealtimePreviewGeometry(
            sourceSize: sourceSize,
            contentRect: contentRect,
            snapshot: snapshot
        )
        let exportPoint = planner.mappedContentPoint(
            for: point,
            in: CGRect(origin: .zero, size: sourceSize),
            cropRect: geometry.cropRect,
            layout: RenderLayout(renderSize: contentRect.size, padding: 0),
            displayRect: geometry.displayRect
        )

        let previewPoint = geometry.contentPoint(for: point)

        XCTAssertEqual(previewPoint.x, exportPoint.x, accuracy: 0.0001)
        XCTAssertEqual(previewPoint.y, exportPoint.y, accuracy: 0.0001)
    }

    func testScreenCaptureBasePresentationFillsOutputCanvas() {
        let planner = SourceCropPlanner()
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let presentation = planner.presentation(
            for: CGRect(x: 0, y: 0, width: 2560, height: 1600),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            captureTarget: .screen
        )

        XCTAssertEqual(presentation.displayRect, contentRect)
        XCTAssertEqual(presentation.cropRect.width, 2560, accuracy: 0.0001)
        XCTAssertLessThan(presentation.cropRect.height, 1600)
        XCTAssertEqual(
            presentation.cropRect.width / presentation.cropRect.height,
            contentRect.width / contentRect.height,
            accuracy: 0.0001
        )
    }

    func testWindowCaptureBasePresentationPreservesFullSource() {
        let planner = SourceCropPlanner()
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let presentation = planner.presentation(
            for: CGRect(x: 0, y: 0, width: 2560, height: 1600),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            captureTarget: .window
        )

        XCTAssertEqual(presentation.cropRect, CGRect(x: 0, y: 0, width: 2560, height: 1600))
        XCTAssertEqual(presentation.displayRect.width, 1440, accuracy: 0.0001)
        XCTAssertEqual(presentation.displayRect.height, 900, accuracy: 0.0001)
        XCTAssertEqual(presentation.displayRect.midX, contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(presentation.displayRect.midY, contentRect.midY, accuracy: 0.0001)
    }

    func testWindowBasePreviewFitsFullSourceWithoutCropping() {
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 900, height: 900),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            preservesFullSourceAtBase: true
        )

        XCTAssertEqual(geometry.cropRect, CGRect(x: 0, y: 0, width: 900, height: 900))
        XCTAssertEqual(geometry.displayRect.width, 900, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.height, 900, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.midX, contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.midY, contentRect.midY, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 0, y: 0)).x, geometry.displayRect.minX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 1, y: 1)).x, geometry.displayRect.maxX, accuracy: 0.0001)
    }

    func testPreservedSourceAspectMapsCornersInsideFittedVideoObject() {
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 2560, height: 1600),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            preservesFullSourceAtBase: true
        )

        XCTAssertEqual(geometry.displayRect.width, 1440, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.height, 900, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.midX, contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 0, y: 0)).x, geometry.displayRect.minX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 0, y: 0)).y, geometry.displayRect.minY, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 1, y: 1)).x, geometry.displayRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 1, y: 1)).y, geometry.displayRect.maxY, accuracy: 0.0001)
    }

    func testPreservedSourceAspectZoomKeepsPointerMappingInVideoObject() {
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let focus = NormalizedPoint(x: 0.22, y: 0.82)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 2560, height: 1600),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: focus, zoom: 1.6, emphasis: .click),
            preservesFullSourceAtBase: true
        )

        XCTAssertEqual(geometry.cropRect.width / geometry.cropRect.height, 2560.0 / 1600.0, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.width, 1440, accuracy: 0.0001)
        XCTAssertEqual(geometry.displayRect.height, 900, accuracy: 0.0001)
        let mapped = geometry.contentPoint(for: focus)
        XCTAssertGreaterThanOrEqual(mapped.x, geometry.displayRect.minX)
        XCTAssertLessThanOrEqual(mapped.x, geometry.displayRect.maxX)
        XCTAssertGreaterThanOrEqual(mapped.y, geometry.displayRect.minY)
        XCTAssertLessThanOrEqual(mapped.y, geometry.displayRect.maxY)
    }

    func testWindowPreviewTransitionsContinuouslyFromFullViewToFocusedCrop() {
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let fullView = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 900, height: 900),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            preservesFullSourceAtBase: true
        )
        let earlyZoom = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 900, height: 900),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.04, emphasis: .none),
            preservesFullSourceAtBase: true
        )
        let focused = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 900, height: 900),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.7, emphasis: .none),
            preservesFullSourceAtBase: true
        )

        XCTAssertEqual(earlyZoom.displayRect.width, fullView.displayRect.width, accuracy: 0.0001)
        XCTAssertEqual(earlyZoom.displayRect.width, focused.displayRect.width, accuracy: 0.0001)
        XCTAssertEqual(earlyZoom.displayRect.height, fullView.displayRect.height, accuracy: 0.0001)
        XCTAssertEqual(earlyZoom.displayRect.height, focused.displayRect.height, accuracy: 0.0001)
        XCTAssertGreaterThan(earlyZoom.cropRect.width, focused.cropRect.width)
        XCTAssertLessThan(earlyZoom.cropRect.width, fullView.cropRect.width)
        XCTAssertEqual(earlyZoom.displayRect.midX, contentRect.midX, accuracy: 0.0001)
        XCTAssertEqual(earlyZoom.displayRect.midY, contentRect.midY, accuracy: 0.0001)
    }

    func testCursorGeometryKeepsTipPinnedToEventPoint() {
        let tip = CGPoint(x: 420, y: 260)
        let scale: CGFloat = 1.35
        let origin = CursorGeometry.origin(forTip: tip, scale: scale)

        XCTAssertEqual((origin.x + CursorGeometry.hotspot.x) * scale, tip.x, accuracy: 0.0001)
        XCTAssertEqual((origin.y + CursorGeometry.hotspot.y) * scale, tip.y, accuracy: 0.0001)
    }

    func testCoreImageCursorTemplateKeepsTipPinnedToEventPoint() {
        let tip = CGPoint(x: 420, y: 260)
        let scale: CGFloat = 1.35
        let origin = CursorGeometry.coreImageTemplateOrigin(forTip: tip, scale: scale)

        XCTAssertEqual(origin.x + (CursorGeometry.coreImageHotspot.x * scale), tip.x, accuracy: 0.0001)
        XCTAssertEqual(origin.y + (CursorGeometry.coreImageHotspot.y * scale), tip.y, accuracy: 0.0001)
        XCTAssertEqual(
            CursorGeometry.coreImageHotspot.y,
            CursorGeometry.templateSize.height - CursorGeometry.hotspot.y,
            accuracy: 0.0001
        )
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

    func testAutoZoomSegmentUsesCameraPlanInsteadOfForcingSegmentFocus() {
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

        let trackedSnapshot = composer.snapshot(at: 1.0, from: keyframes, manualZoomSegments: [auto])

        XCTAssertEqual(trackedSnapshot.focus.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(trackedSnapshot.focus.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(trackedSnapshot.zoom, 1.6, accuracy: 0.0001)
    }

    func testAutoZoomTrackMasksCameraPlanOutsideAutoSegments() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 1, focus: .init(x: 0.7, y: 0.3), zoom: 1.6),
            CameraKeyframe(timestamp: 2, focus: .init(x: 0.2, y: 0.8), zoom: 1.5)
        ]
        let auto = ManualZoomSegment(
            start: 0.8,
            end: 1.2,
            focus: .init(x: 0.1, y: 0.9),
            zoomLevel: 2.2,
            easeInDuration: 0,
            easeOutDuration: 0,
            source: .auto
        )

        let beforeSegment = composer.snapshot(at: 0.5, from: keyframes, manualZoomSegments: [auto])
        let insideSegment = composer.snapshot(at: 1.0, from: keyframes, manualZoomSegments: [auto])

        XCTAssertEqual(beforeSegment.focus.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(beforeSegment.focus.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(beforeSegment.zoom, 1.0, accuracy: 0.0001)
        XCTAssertEqual(insideSegment.focus.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(insideSegment.focus.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(insideSegment.zoom, 1.6, accuracy: 0.0001)
    }

    func testEditedEmptyZoomTrackSuppressesCameraZoom() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 1, focus: .init(x: 0.7, y: 0.3), zoom: 1.6)
        ]

        let snapshot = composer.snapshot(
            at: 1.0,
            from: keyframes,
            manualZoomSegments: [],
            zoomTrackEdited: true
        )

        XCTAssertEqual(snapshot.focus.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.focus.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.zoom, 1.0, accuracy: 0.0001)
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

    func testContiguousManualZoomSegmentsEaseFromPreviousFocusInsteadOfCenter() {
        let composer = FrameComposer()
        let keyframes = [
            CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0),
            CameraKeyframe(timestamp: 3, focus: .center, zoom: 1.0)
        ]
        let first = ManualZoomSegment(
            start: 0.5,
            end: 1.5,
            focus: .init(x: 0.1, y: 0.2),
            zoomLevel: 1.8,
            easeInDuration: 0.08,
            easeOutDuration: 0,
            source: .manual
        )
        let second = ManualZoomSegment(
            start: 1.5,
            end: 2.5,
            focus: .init(x: 0.9, y: 0.8),
            zoomLevel: 2.1,
            easeInDuration: 0.08,
            easeOutDuration: 0,
            source: .manual
        )

        let boundary = composer.snapshot(at: 1.5, from: keyframes, manualZoomSegments: [first, second])
        let midTransition = composer.snapshot(at: 1.54, from: keyframes, manualZoomSegments: [first, second])
        let settled = composer.snapshot(at: 1.58, from: keyframes, manualZoomSegments: [first, second])

        XCTAssertEqual(boundary.focus.x, first.focus.x, accuracy: 0.0001)
        XCTAssertEqual(boundary.focus.y, first.focus.y, accuracy: 0.0001)
        XCTAssertGreaterThan(midTransition.focus.x, first.focus.x)
        XCTAssertLessThan(midTransition.focus.x, second.focus.x)
        XCTAssertEqual(settled.focus.x, second.focus.x, accuracy: 0.0001)
        XCTAssertEqual(settled.focus.y, second.focus.y, accuracy: 0.0001)
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
