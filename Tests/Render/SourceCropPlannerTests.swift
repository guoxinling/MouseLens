import AVFoundation
import AVKit
import CoreGraphics
import CoreImage
import ImageIO
import XCTest
@testable import MouseLens

final class SourceCropPlannerTests: XCTestCase {
    func testPreviewPlayerUsesResizeGravityBecauseGeometryAlreadyAppliesCrop() {
        XCTAssertEqual(PreviewVideoGravityPolicy.playerVideoGravity, .resize)
    }

    func testMP4ExportComposesPresenterBubbleOverSourceVideo() async throws {
        let directory = try Self.makeTemporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source.mp4")
        let presenterURL = directory.appendingPathComponent("presenter.mp4")
        let outputURL = directory.appendingPathComponent("output.mp4")
        try Self.writeSolidVideo(to: sourceURL, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        try Self.writeSolidVideo(to: presenterURL, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .topLeft,
            normalizedSize: 0.22,
            shape: .roundedRect,
            cornerRadius: 8,
            shadowOpacity: 0
        )
        let project = Self.project(
            sourceVideoURL: sourceURL,
            style: .testValue(replacingPresenterBubbleStyleWith: style),
            presenterMedia: PresenterMedia(
                sourceVideoURL: presenterURL,
                startedAt: nil,
                renderOffset: 0,
                naturalSize: CGSize(width: 64, height: 36)
            )
        )
        let configuration = ExportConfiguration(
            format: .mp4,
            resolution: .p480,
            frameRate: .fps15,
            quality: .small,
            includesCursor: false,
            includesClickFeedback: false
        )

        _ = try await VideoRenderer().renderVideo(for: project, configuration: configuration, destinationURL: outputURL)

        let frame = try Self.firstVideoFrame(from: outputURL)
        let samplePoint = Self.presenterSamplePoint(style: style, renderSize: configuration.renderSize(for: .landscape))
        let pixel = try Self.pixel(in: frame, atTopOriginPoint: samplePoint)
        XCTAssertGreaterThan(pixel.red, 0.72)
        XCTAssertLessThan(pixel.blue, 0.28)
    }

    func testGIFExportComposesPresenterBubbleOverSourceVideo() async throws {
        let directory = try Self.makeTemporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source.mp4")
        let presenterURL = directory.appendingPathComponent("presenter.mp4")
        let outputURL = directory.appendingPathComponent("output.gif")
        try Self.writeSolidVideo(to: sourceURL, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        try Self.writeSolidVideo(to: presenterURL, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .topRight,
            normalizedSize: 0.2,
            shape: .circle,
            cornerRadius: 0,
            shadowOpacity: 0
        )
        let project = Self.project(
            sourceVideoURL: sourceURL,
            style: .testValue(replacingPresenterBubbleStyleWith: style),
            presenterMedia: PresenterMedia(
                sourceVideoURL: presenterURL,
                startedAt: nil,
                renderOffset: 0,
                naturalSize: CGSize(width: 64, height: 36)
            )
        )
        var configuration = ExportConfiguration.recommended(for: .landscape, format: .gif)
        configuration.resolution = .p720

        _ = try await VideoRenderer().renderVideo(for: project, configuration: configuration, destinationURL: outputURL)

        let frame = try Self.firstGIFFrame(from: outputURL)
        let samplePoint = Self.presenterSamplePoint(style: style, renderSize: configuration.renderSize(for: .landscape))
        let pixel = try Self.pixel(in: frame, atTopOriginPoint: samplePoint)
        XCTAssertGreaterThan(pixel.red, 0.72)
        XCTAssertLessThan(pixel.blue, 0.28)
    }

    func testExportFallsBackWhenPresenterFrameCannotDecode() async throws {
        let directory = try Self.makeTemporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source.mp4")
        let presenterURL = directory.appendingPathComponent("invalid-presenter.mp4")
        let outputURL = directory.appendingPathComponent("output.mp4")
        try Self.writeSolidVideo(to: sourceURL, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        try Data("not a movie".utf8).write(to: presenterURL)

        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .topLeft,
            normalizedSize: 0.22,
            shape: .roundedRect,
            cornerRadius: 8,
            shadowOpacity: 0
        )
        let project = Self.project(
            sourceVideoURL: sourceURL,
            style: .testValue(replacingPresenterBubbleStyleWith: style),
            presenterMedia: PresenterMedia(
                sourceVideoURL: presenterURL,
                startedAt: nil,
                renderOffset: 0,
                naturalSize: CGSize(width: 64, height: 36)
            )
        )
        let configuration = ExportConfiguration(
            format: .mp4,
            resolution: .p480,
            frameRate: .fps15,
            quality: .small,
            includesCursor: false,
            includesClickFeedback: false
        )

        _ = try await VideoRenderer().renderVideo(for: project, configuration: configuration, destinationURL: outputURL)

        let frame = try Self.firstVideoFrame(from: outputURL)
        let samplePoint = CGPoint(x: CGFloat(frame.width) / 2, y: CGFloat(frame.height) / 2)
        let pixel = try Self.pixel(in: frame, atTopOriginPoint: samplePoint)
        XCTAssertGreaterThan(pixel.blue, 0.72)
        XCTAssertLessThan(pixel.red, 0.28)
    }

    func testPresenterExportPlanUsesOverlayGeometryAndOffsetTimestamp() throws {
        let presenterURL = URL(fileURLWithPath: "/tmp/presenter.mov")
        let style = PresenterBubbleStyle(
            isEnabled: true,
            position: .topLeft,
            normalizedSize: 0.2,
            shape: .roundedRect,
            cornerRadius: 22,
            shadowOpacity: 0.31
        )
        let project = Self.project(
            style: .testValue(replacingPresenterBubbleStyleWith: style),
            presenterMedia: PresenterMedia(
                sourceVideoURL: presenterURL,
                startedAt: Date(timeIntervalSince1970: 2),
                renderOffset: -1.25,
                naturalSize: CGSize(width: 1280, height: 720)
            )
        )
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0.08)

        let plan = try XCTUnwrap(PresenterExportOverlayPlan.make(
            for: project,
            layout: layout,
            sourceTimestamp: 0.5,
            fileExists: { $0 == presenterURL }
        ))

        XCTAssertEqual(plan.sourceVideoURL, presenterURL)
        XCTAssertEqual(plan.layout, PresenterOverlayGeometry.layout(contentRect: layout.fullRect, style: style))
        XCTAssertEqual(plan.timestamp, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.shadowOpacity, 0.31, accuracy: 0.0001)
    }

    func testPresenterExportPlanSkipsUnavailablePresenterBubbleInputs() {
        let presenterURL = URL(fileURLWithPath: "/tmp/presenter.mov")
        let enabledStyle = PresenterBubbleStyle.defaultValue
        let disabledStyle = PresenterBubbleStyle(
            isEnabled: false,
            position: .bottomRight,
            normalizedSize: 0.26,
            shape: .circle,
            cornerRadius: 18,
            shadowOpacity: 0.24
        )
        let layout = RenderLayout(renderSize: CGSize(width: 1920, height: 1080), padding: 0.08)
        let media = PresenterMedia(
            sourceVideoURL: presenterURL,
            startedAt: nil,
            renderOffset: 0.2,
            naturalSize: CGSize(width: 1280, height: 720)
        )

        XCTAssertNil(PresenterExportOverlayPlan.make(
            for: Self.project(style: .testValue(replacingPresenterBubbleStyleWith: disabledStyle), presenterMedia: media),
            layout: layout,
            sourceTimestamp: 1,
            fileExists: { _ in true }
        ))
        XCTAssertNil(PresenterExportOverlayPlan.make(
            for: Self.project(style: .testValue(replacingPresenterBubbleStyleWith: enabledStyle), presenterMedia: nil),
            layout: layout,
            sourceTimestamp: 1,
            fileExists: { _ in true }
        ))
        XCTAssertNil(PresenterExportOverlayPlan.make(
            for: Self.project(style: .testValue(replacingPresenterBubbleStyleWith: enabledStyle), presenterMedia: media),
            layout: layout,
            sourceTimestamp: 1,
            fileExists: { _ in false }
        ))
    }

    func testBaseCropKeepsRequestedAspectRatioCentered() {
        let planner = SourceCropPlanner()
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let crop = planner.baseCropRect(for: source, outputAspectRatio: 9.0 / 16.0)

        XCTAssertEqual(crop.width / crop.height, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(crop.midX, source.midX, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, source.midY, accuracy: 0.0001)
    }

    func testFocusedCropClampsToSourceBoundsNearEdges() {
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

        XCTAssertGreaterThanOrEqual(crop.minX, source.minX - 0.0001)
        XCTAssertGreaterThanOrEqual(crop.minY, source.minY - 0.0001)
        XCTAssertLessThanOrEqual(crop.maxX, source.maxX + 0.0001)
        XCTAssertLessThanOrEqual(crop.maxY, source.maxY + 0.0001)
        XCTAssertEqual(crop.maxX, source.maxX, accuracy: 0.0001)
        XCTAssertEqual(crop.maxY, source.maxY, accuracy: 0.0001)
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

    func testMappedContentPointStaysVisibleForEdgeAnchoredCrop() {
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

        XCTAssertGreaterThanOrEqual(mappedPoint.x, layout.contentRect.minX)
        XCTAssertLessThan(mappedPoint.x, layout.contentRect.midX)
        XCTAssertGreaterThanOrEqual(mappedPoint.y, layout.contentRect.minY)
        XCTAssertLessThan(mappedPoint.y, layout.contentRect.midY)
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

    func testRenderLayoutAllowsZeroPaddingToFillOutputCanvas() {
        let renderSize = CGSize(width: 1920, height: 1080)
        let layout = RenderLayout(renderSize: renderSize, padding: 0)

        XCTAssertEqual(layout.contentRect, CGRect(origin: .zero, size: renderSize))
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

    func testWindowCaptureZeroPaddingFillsOutputCanvasInsteadOfLetterboxing() {
        let renderLayout = RenderLayout(renderSize: CGSize(width: 1600, height: 900), padding: 0)
        let shouldPreserveFullSource = SourcePresentationPolicy.preservesFullSourceAtBase(
            captureTarget: .window,
            padding: 0
        )
        let presentation = SourceCropPlanner().presentation(
            for: CGRect(x: 0, y: 0, width: 2560, height: 1600),
            contentRect: renderLayout.contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            preservesFullSourceAtBase: shouldPreserveFullSource
        )

        XCTAssertFalse(shouldPreserveFullSource)
        XCTAssertEqual(presentation.displayRect, renderLayout.contentRect)
        XCTAssertEqual(presentation.cropRect.width / presentation.cropRect.height, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testWindowCaptureNonZeroPaddingKeepsFullSourceInsideBackground() {
        let shouldPreserveFullSource = SourcePresentationPolicy.preservesFullSourceAtBase(
            captureTarget: .window,
            padding: 0.04
        )

        XCTAssertTrue(shouldPreserveFullSource)
    }

    func testScreenCaptureNonZeroPaddingKeepsFullSourceForCursorAlignment() {
        let shouldPreserveFullSource = SourcePresentationPolicy.preservesFullSourceAtBase(
            captureTarget: .screen,
            padding: 0.04
        )

        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 1470, height: 956),
            contentRect: contentRect,
            snapshot: FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none),
            preservesFullSourceAtBase: shouldPreserveFullSource
        )

        XCTAssertTrue(shouldPreserveFullSource)
        XCTAssertEqual(geometry.cropRect, CGRect(x: 0, y: 0, width: 1470, height: 956))
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 0, y: 0)).x, geometry.displayRect.minX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 0, y: 0)).y, geometry.displayRect.minY, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 1, y: 1)).x, geometry.displayRect.maxX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentPoint(for: .init(x: 1, y: 1)).y, geometry.displayRect.maxY, accuracy: 0.0001)
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

    func testWindowZoomNearSourceEdgeDoesNotCropOutsideSourceBounds() {
        let contentRect = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let geometry = RealtimePreviewGeometry(
            sourceSize: CGSize(width: 2940, height: 1846),
            contentRect: contentRect,
            snapshot: FrameSnapshot(
                focus: NormalizedPoint(x: 0.12923309948979592, y: 0.9754875406283857),
                zoom: 1.4088400748388252,
                emphasis: .click
            ),
            preservesFullSourceAtBase: true
        )

        XCTAssertGreaterThanOrEqual(geometry.cropRect.minX, -0.0001)
        XCTAssertGreaterThanOrEqual(geometry.cropRect.minY, -0.0001)
        XCTAssertLessThanOrEqual(geometry.cropRect.maxX, 2940.0001)
        XCTAssertLessThanOrEqual(geometry.cropRect.maxY, 1846.0001)
        let effectivePlayerFrame = geometry.videoFrame.offsetBy(
            dx: -geometry.displayRect.minX,
            dy: -geometry.displayRect.minY
        )
        XCTAssertLessThanOrEqual(effectivePlayerFrame.minX, 0.0001)
        XCTAssertLessThanOrEqual(effectivePlayerFrame.minY, 0.0001)
        XCTAssertGreaterThanOrEqual(effectivePlayerFrame.maxX, geometry.displayRect.width - 0.0001)
        XCTAssertGreaterThanOrEqual(effectivePlayerFrame.maxY, geometry.displayRect.height - 0.0001)
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

    func testFullscreenBrowserWindowCursorVisualCalibrationAppliesSmallUpwardOffset() {
        let offset = CursorVisualCalibrationPolicy.offset(
            captureTarget: .window,
            sourceSize: CGSize(width: 2940, height: 1670),
            sourceExtent: CGRect(x: 0, y: 0, width: 2660, height: 1670)
        )

        XCTAssertEqual(offset.width, 0, accuracy: 0.0001)
        XCTAssertEqual(offset.height, -3, accuracy: 0.0001)
    }

    func testCursorVisualCalibrationDoesNotAffectScreenOrOrdinaryWindow() {
        let screenOffset = CursorVisualCalibrationPolicy.offset(
            captureTarget: .screen,
            sourceSize: CGSize(width: 2940, height: 1670),
            sourceExtent: CGRect(x: 0, y: 0, width: 2660, height: 1670)
        )
        let ordinaryWindowOffset = CursorVisualCalibrationPolicy.offset(
            captureTarget: .window,
            sourceSize: CGSize(width: 2940, height: 1670),
            sourceExtent: CGRect(x: 0, y: 0, width: 2940, height: 1670)
        )

        XCTAssertEqual(screenOffset.width, 0, accuracy: 0.0001)
        XCTAssertEqual(screenOffset.height, 0, accuracy: 0.0001)
        XCTAssertEqual(ordinaryWindowOffset.width, 0, accuracy: 0.0001)
        XCTAssertEqual(ordinaryWindowOffset.height, 0, accuracy: 0.0001)
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

    private static func project(
        sourceVideoURL: URL = URL(fileURLWithPath: "/tmp/source.mov"),
        style: ProjectStyle,
        presenterMedia: PresenterMedia?
    ) -> RecordingProject {
        RecordingProject(
            id: UUID(),
            name: "Presenter Export",
            createdAt: Date(timeIntervalSince1970: 0),
            duration: 6,
            sourceVideoURL: sourceVideoURL,
            captureTarget: .screen,
            reconstructsCursor: true,
            events: [],
            cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1)],
            style: style,
            presenterMedia: presenterMedia
        )
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeSolidVideo(
        to url: URL,
        color: CGColor,
        size: CGSize = CGSize(width: 64, height: 36),
        frameRate: Int32 = 15,
        frameCount: Int = 4
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard let buffer = makePixelBuffer(size: size, color: color) else {
                throw VideoRendererError.unableToCreatePixelBuffer
            }
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: time))
        }

        input.markAsFinished()
        let expectation = XCTestExpectation(description: "finish writing solid video")
        writer.finishWriting {
            expectation.fulfill()
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: 5)
        if writer.status != .completed {
            throw writer.error ?? VideoRendererError.writerFailed
        }
    }

    private static func makePixelBuffer(size: CGSize, color: CGColor) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size))
        return buffer
    }

    private static func firstVideoFrame(from url: URL) throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(at: .zero, actualTime: nil)
    }

    private static func firstGIFFrame(from url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let frame = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw VideoRendererError.exportFailed
        }
        return frame
    }

    private static func presenterSamplePoint(style: PresenterBubbleStyle, renderSize: CGSize) -> CGPoint {
        let renderLayout = RenderLayout(renderSize: renderSize, padding: 0.08)
        let layout = PresenterOverlayGeometry.layout(
            contentRect: renderLayout.fullRect,
            style: style
        )
        return CGPoint(x: layout.frame.midX, y: layout.frame.midY)
    }

    private static func pixel(in image: CGImage, atTopOriginPoint point: CGPoint) throws -> (red: Double, green: Double, blue: Double) {
        let ciImage = CIImage(cgImage: image)
        let context = CIContext(options: [.cacheIntermediates: false])
        let x = point.x.rounded(.down).clamped(to: 0...CGFloat(max(image.width - 1, 0)))
        let y = (CGFloat(image.height) - point.y.rounded(.down) - 1).clamped(to: 0...CGFloat(max(image.height - 1, 0)))
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            ciImage.cropped(to: CGRect(x: x, y: y, width: 1, height: 1)),
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (
            red: Double(pixel[0]) / 255.0,
            green: Double(pixel[1]) / 255.0,
            blue: Double(pixel[2]) / 255.0
        )
    }
}

private extension ProjectStyle {
    static func testValue(replacingPresenterBubbleStyleWith presenterBubbleStyle: PresenterBubbleStyle) -> ProjectStyle {
        ProjectStyle(
            aspectRatio: .landscape,
            backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
            cornerRadius: 26,
            shadowRadius: 18,
            followStrength: 0.6,
            clickEmphasis: 0.7,
            padding: 0.08,
            presenterBubbleStyle: presenterBubbleStyle
        )
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
