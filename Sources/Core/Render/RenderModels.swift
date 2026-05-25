import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import CoreImage
import CoreVideo
import Foundation

enum ExportPreset: String, CaseIterable {
    case standardLandscape
    case standardPortrait
    case squareSocial

    var label: String {
        switch self {
        case .standardLandscape: "1080p Landscape"
        case .standardPortrait: "1080p Portrait"
        case .squareSocial: "1080 Square"
        }
    }

    var aspectRatio: ProjectAspectRatio {
        switch self {
        case .standardLandscape: .landscape
        case .standardPortrait: .portrait
        case .squareSocial: .square
        }
    }

    var renderSize: CGSize {
        switch self {
        case .standardLandscape:
            CGSize(width: 1920, height: 1080)
        case .standardPortrait:
            CGSize(width: 1080, height: 1920)
        case .squareSocial:
            CGSize(width: 1080, height: 1080)
        }
    }

    static func defaultPreset(for aspectRatio: ProjectAspectRatio) -> ExportPreset {
        switch aspectRatio {
        case .landscape: .standardLandscape
        case .portrait: .standardPortrait
        case .square: .squareSocial
        }
    }
}

enum VideoRendererError: LocalizedError {
    case missingSourceVideo
    case legacySourceRequiresRecapture
    case unableToCreateWriter
    case unableToCreatePixelBuffer
    case unableToCreateContext
    case unableToCreateExportSession
    case writerFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingSourceVideo:
            "MouseLens could not find the raw recording for export."
        case .legacySourceRequiresRecapture:
            "This recording came from an older capture pipeline that MouseLens can preview but cannot reliably process for export. Please record it again in the latest build and export the new clip."
        case .unableToCreateWriter:
            "MouseLens could not create a video writer."
        case .unableToCreatePixelBuffer:
            "MouseLens could not allocate a frame buffer."
        case .unableToCreateContext:
            "MouseLens could not prepare the drawing context."
        case .unableToCreateExportSession:
            "MouseLens could not create the export session."
        case .writerFailed:
            "MouseLens could not finish writing the exported video."
        case .exportFailed:
            "MouseLens could not finish exporting the processed video."
        }
    }
}

struct FrameSnapshot: Equatable {
    let focus: NormalizedPoint
    let zoom: Double
    let emphasis: CameraKeyframe.EmphasisKind
}

struct PointerSnapshot: Equatable {
    let rawLocation: NormalizedPoint
    let location: NormalizedPoint
    let clickLocation: NormalizedPoint?
    let clickProgress: Double

    var isClickActive: Bool {
        clickProgress > 0.001
    }
}

enum PointerSmoothingMode {
    case smoothed
    case raw
}

enum CursorGeometry {
    static let templateSize = CGSize(width: 44, height: 44)
    static let hotspot = CGPoint(x: 5, y: 5)

    static func origin(forTip tip: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (tip.x / max(scale, 0.0001)) - hotspot.x,
            y: (tip.y / max(scale, 0.0001)) - hotspot.y
        )
    }
}

protocol ProjectPreviewRendering {
    @MainActor
    func makePreviewImage(
        for project: RecordingProject,
        preset: ExportPreset,
        timestamp: TimeInterval
    ) async throws -> NSImage?

    @MainActor
    func renderPreviewVideo(
        for project: RecordingProject,
        preset: ExportPreset,
        destinationURL: URL
    ) async throws -> URL
}

struct PointerTimeline {
    private let clickHighlightDuration: TimeInterval = 0.26
    private let smoothingWindow: TimeInterval = 0.13
    private let maximumSmoothingDistance = 0.042

    func snapshot(
        at timestamp: TimeInterval,
        from events: [PointerEvent],
        smoothing: PointerSmoothingMode = .smoothed
    ) -> PointerSnapshot? {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        let rawLocation = interpolatedLocation(at: timestamp, from: sorted)
        let click = latestClick(at: timestamp, from: sorted)
        let clickProgress = clickProgress(at: timestamp, click: click)
        let location: NormalizedPoint
        switch smoothing {
        case .smoothed:
            location = smoothedLocation(
                rawLocation: rawLocation,
                timestamp: timestamp,
                events: sorted,
                activeClick: click
            )
        case .raw:
            location = rawLocation
        }

        return PointerSnapshot(
            rawLocation: rawLocation,
            location: location,
            clickLocation: clickProgress > 0 ? click?.location : nil,
            clickProgress: clickProgress
        )
    }

    private func interpolatedLocation(at timestamp: TimeInterval, from events: [PointerEvent]) -> NormalizedPoint {
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

    private func smoothedLocation(
        rawLocation: NormalizedPoint,
        timestamp: TimeInterval,
        events: [PointerEvent],
        activeClick: PointerEvent?
    ) -> NormalizedPoint {
        if let activeClick, abs(timestamp - activeClick.timestamp) <= 0.001 {
            return activeClick.location
        }

        var weightedX = rawLocation.x * 1.8
        var weightedY = rawLocation.y * 1.8
        var totalWeight = 1.8

        for event in events where event.type != .click {
            let distance = abs(event.timestamp - timestamp)
            guard distance <= smoothingWindow else { continue }

            let normalizedDistance = (distance / smoothingWindow).clamped(to: 0...1)
            let weight = pow(1 - normalizedDistance, 2)
            weightedX += event.location.x * weight
            weightedY += event.location.y * weight
            totalWeight += weight
        }

        let averaged = NormalizedPoint(
            x: (weightedX / max(totalWeight, 0.0001)).clamped(to: 0...1),
            y: (weightedY / max(totalWeight, 0.0001)).clamped(to: 0...1)
        )
        return rawLocation.limitedToward(averaged, maxDistance: maximumSmoothingDistance)
    }

    private func latestClick(at timestamp: TimeInterval, from events: [PointerEvent]) -> PointerEvent? {
        events.last { $0.type == .click && $0.timestamp <= timestamp }
    }

    private func clickProgress(at timestamp: TimeInterval, click: PointerEvent?) -> Double {
        guard let click else { return 0 }

        let delta = timestamp - click.timestamp
        guard delta <= clickHighlightDuration else {
            return 0
        }

        let progress = 1 - (delta / clickHighlightDuration)
        return pow(progress.clamped(to: 0...1), 1.15)
    }
}

struct FrameComposer {
    func snapshot(at timestamp: TimeInterval, from keyframes: [CameraKeyframe]) -> FrameSnapshot {
        guard let first = keyframes.first else {
            return FrameSnapshot(focus: .center, zoom: 1.0, emphasis: .none)
        }

        guard let last = keyframes.last else {
            return FrameSnapshot(focus: first.focus, zoom: first.zoom, emphasis: first.emphasis)
        }

        if timestamp <= first.timestamp {
            return FrameSnapshot(focus: first.focus, zoom: first.zoom, emphasis: first.emphasis)
        }

        if timestamp >= last.timestamp {
            return FrameSnapshot(focus: last.focus, zoom: last.zoom, emphasis: last.emphasis)
        }

        guard let upperIndex = keyframes.firstIndex(where: { $0.timestamp >= timestamp }), upperIndex > 0 else {
            return FrameSnapshot(focus: last.focus, zoom: last.zoom, emphasis: last.emphasis)
        }

        let lower = keyframes[upperIndex - 1]
        let upper = keyframes[upperIndex]
        let span = max(upper.timestamp - lower.timestamp, 0.0001)
        let progress = ((timestamp - lower.timestamp) / span).clamped(to: 0...1)

        let focus = NormalizedPoint(
            x: lower.focus.x + ((upper.focus.x - lower.focus.x) * progress),
            y: lower.focus.y + ((upper.focus.y - lower.focus.y) * progress)
        )
        let zoom = lower.zoom + ((upper.zoom - lower.zoom) * progress)
        let emphasis: CameraKeyframe.EmphasisKind = (progress < 0.5) ? lower.emphasis : upper.emphasis
        return FrameSnapshot(focus: focus, zoom: zoom, emphasis: emphasis)
    }

    func snapshot(
        at timestamp: TimeInterval,
        from keyframes: [CameraKeyframe],
        manualZoomSegments: [ManualZoomSegment]
    ) -> FrameSnapshot {
        let baseSnapshot = snapshot(at: timestamp, from: keyframes)
        guard let segment = activeManualZoomSegment(at: timestamp, in: manualZoomSegments) else {
            return baseSnapshot
        }

        let blend = manualZoomBlend(at: timestamp, in: segment)
        guard blend > 0 else { return baseSnapshot }

        let focus = NormalizedPoint(
            x: baseSnapshot.focus.x + ((segment.focus.x - baseSnapshot.focus.x) * blend),
            y: baseSnapshot.focus.y + ((segment.focus.y - baseSnapshot.focus.y) * blend)
        )
        let zoom = baseSnapshot.zoom + ((segment.zoomLevel - baseSnapshot.zoom) * blend)
        return FrameSnapshot(
            focus: focus,
            zoom: zoom.clamped(to: ManualZoomSegment.zoomRange),
            emphasis: baseSnapshot.emphasis
        )
    }

    private func activeManualZoomSegment(
        at timestamp: TimeInterval,
        in segments: [ManualZoomSegment]
    ) -> ManualZoomSegment? {
        segments
            .filter { $0.source == .manual }
            .filter { timestamp >= $0.start && timestamp <= $0.end }
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source == .auto
                }
                return lhs.start < rhs.start
            }
            .last
    }

    private func manualZoomBlend(at timestamp: TimeInterval, in segment: ManualZoomSegment) -> Double {
        let elapsed = timestamp - segment.start
        let remaining = segment.end - timestamp
        var blend = 1.0

        if segment.easeInDuration > 0 {
            blend = min(blend, elapsed / segment.easeInDuration)
        }

        if segment.easeOutDuration > 0 {
            blend = min(blend, remaining / segment.easeOutDuration)
        }

        let progress = blend.clamped(to: 0...1)
        return progress * progress * (3 - (2 * progress))
    }
}

struct SourceCropPlanner {
    func cropRect(
        for sourceExtent: CGRect,
        outputAspectRatio: CGFloat,
        snapshot: FrameSnapshot
    ) -> CGRect {
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return sourceExtent }

        let baseCrop = baseCropRect(for: sourceExtent, outputAspectRatio: outputAspectRatio)
        let zoom = snapshot.zoom.clamped(to: ManualZoomSegment.zoomRange)
        let cropWidth = baseCrop.width / zoom
        let cropHeight = baseCrop.height / zoom

        // CameraPlanEngine already clamps focus away from unstable screen edges.
        // Using the full source extent here keeps click emphasis aligned with the
        // actual pointer location instead of introducing an extra vertical offset.
        let centerX = sourceExtent.minX + (snapshot.focus.x * sourceExtent.width)
        let centerY = sourceExtent.maxY - (snapshot.focus.y * sourceExtent.height)

        let minX = sourceExtent.minX
        let maxX = sourceExtent.maxX - cropWidth
        let minY = sourceExtent.minY
        let maxY = sourceExtent.maxY - cropHeight

        let originX = (centerX - (cropWidth / 2)).clamped(to: minX...max(maxX, minX))
        let originY = (centerY - (cropHeight / 2)).clamped(to: minY...max(maxY, minY))

        return CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
    }

    func baseCropRect(for sourceExtent: CGRect, outputAspectRatio: CGFloat) -> CGRect {
        let sourceAspectRatio = sourceExtent.width / sourceExtent.height

        if sourceAspectRatio > outputAspectRatio {
            let width = sourceExtent.height * outputAspectRatio
            let x = sourceExtent.midX - (width / 2)
            return CGRect(x: x, y: sourceExtent.minY, width: width, height: sourceExtent.height)
        } else {
            let height = sourceExtent.width / outputAspectRatio
            let y = sourceExtent.midY - (height / 2)
            return CGRect(x: sourceExtent.minX, y: y, width: sourceExtent.width, height: height)
        }
    }

    func mappedContentPoint(
        for focus: NormalizedPoint,
        in sourceExtent: CGRect,
        cropRect: CGRect,
        layout: RenderLayout
    ) -> CGPoint {
        let sourcePoint = CGPoint(
            x: sourceExtent.minX + (focus.x * sourceExtent.width),
            y: sourceExtent.maxY - (focus.y * sourceExtent.height)
        )

        let relativeX = ((sourcePoint.x - cropRect.minX) / max(cropRect.width, 1)).clamped(to: 0...1)
        let relativeY = ((sourcePoint.y - cropRect.minY) / max(cropRect.height, 1)).clamped(to: 0...1)

        return CGPoint(
            x: layout.contentRect.minX + (CGFloat(relativeX) * layout.contentRect.width),
            y: layout.contentRect.minY + (CGFloat(relativeY) * layout.contentRect.height)
        )
    }
}

struct RenderLayout {
    let renderSize: CGSize
    let fullRect: CGRect
    let contentRect: CGRect

    init(renderSize: CGSize, padding: Double) {
        self.renderSize = renderSize
        fullRect = CGRect(origin: .zero, size: renderSize)

        let horizontalInset = renderSize.width > 0 ? padding * renderSize.width : 0
        let verticalInset = renderSize.height > 0 ? padding * renderSize.height : 0
        contentRect = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: max(renderSize.width - (horizontalInset * 2), 1),
            height: max(renderSize.height - (verticalInset * 2), 1)
        )
    }

    var outputAspectRatio: CGFloat {
        contentRect.width / max(contentRect.height, 1)
    }
}

private struct PreparedRenderAssets {
    let layout: RenderLayout
    let backgroundImage: CIImage
    let transparentCanvas: CIImage
    let maskImage: CIImage
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}

final class VideoRenderer: ProjectPreviewRendering, @unchecked Sendable {
    private let composer = FrameComposer()
    private let pointerTimeline = PointerTimeline()
    private let cropPlanner = SourceCropPlanner()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let previewLongestSide: CGFloat = 1280
    private let previewVideoLongestSide: CGFloat = 960
    private let exportFPS: Int32 = 30
    private let sourceFrameSeekTolerance = CMTime(value: 1, timescale: 12)
    private let renderColorSpace = CGColorSpaceCreateDeviceRGB()
    private lazy var cursorTemplateImage: CIImage = makeCursorTemplateImage()

    func renderVideo(for project: RecordingProject, preset: ExportPreset, destinationURL: URL) async throws -> URL {
        guard let sourceURL = project.sourceVideoURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            return try await renderDebugVideo(for: project, preset: preset, destinationURL: destinationURL)
        }

        return try await renderSourceVideo(
            for: project,
            sourceURL: sourceURL,
            renderSize: preset.renderSize,
            destinationURL: destinationURL
        )
    }

    func renderPreviewVideo(
        for project: RecordingProject,
        preset: ExportPreset,
        destinationURL: URL
    ) async throws -> URL {
        let renderSize = previewVideoRenderSize(for: preset.renderSize)
        guard let sourceURL = project.sourceVideoURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            return try await renderDebugVideo(for: project, renderSize: renderSize, destinationURL: destinationURL)
        }

        return try await renderSourceVideo(
            for: project,
            sourceURL: sourceURL,
            renderSize: renderSize,
            destinationURL: destinationURL
        )
    }

    func makePreviewImage(
        for project: RecordingProject,
        preset: ExportPreset,
        timestamp: TimeInterval
    ) async throws -> NSImage? {
        guard let sourceURL = project.sourceVideoURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let renderSize = previewRenderSize(for: preset.renderSize)
        let trimRange = project.effectiveTrimRange
        let clampedTimestamp = timestamp.clamped(to: trimRange.start...trimRange.end)
        let snapshot = composer.snapshot(
            at: clampedTimestamp,
            from: project.cameraKeyframes,
            manualZoomSegments: project.manualZoomSegments
        )
        let pointerSnapshot = pointerTimeline.snapshot(at: clampedTimestamp, from: project.events, smoothing: .raw)

        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = renderSize
        generator.requestedTimeToleranceBefore = sourceFrameSeekTolerance
        generator.requestedTimeToleranceAfter = sourceFrameSeekTolerance

        let time = CMTime(seconds: clampedTimestamp, preferredTimescale: 600)
        let sourceFrame = try await generateSourceFrame(from: generator, at: time)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let sourceImage = CIImage(cgImage: sourceFrame)
                let preparedAssets = prepareAssets(renderSize: renderSize, style: project.style)
                let composedFrame = composeFrame(
                    from: sourceImage,
                    snapshot: snapshot,
                    pointerSnapshot: pointerSnapshot,
                    project: project,
                    preparedAssets: preparedAssets
                )

                guard let outputImage = ciContext.createCGImage(composedFrame, from: preparedAssets.layout.fullRect) else {
                    continuation.resume(throwing: VideoRendererError.unableToCreateContext)
                    return
                }

                continuation.resume(returning: NSImage(cgImage: outputImage, size: renderSize))
            }
        }
    }

    func renderDebugVideo(for project: RecordingProject, preset: ExportPreset, destinationURL: URL) async throws -> URL {
        try await renderDebugVideo(for: project, renderSize: preset.renderSize, destinationURL: destinationURL)
    }

    private func renderDebugVideo(for project: RecordingProject, renderSize: CGSize, destinationURL: URL) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        let size = renderSize
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw VideoRendererError.unableToCreateWriter
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let clipSegments = project.effectiveClipSegments
        let duration = max(totalDuration(of: clipSegments), 1.0 / Double(fps))
        let totalFrames = max(Int(ceil(duration * Double(fps))), 1)
        let frameDuration = CMTime(value: 1, timescale: fps)

        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()

            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            autoreleasepool {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                let outputTimestamp = min(Double(frameIndex) / Double(fps), max(duration - (1.0 / Double(fps)), 0))
                let timestamp = sourceTimestamp(atClipOffset: outputTimestamp, in: clipSegments)
                let snapshot = composer.snapshot(
                    at: timestamp,
                    from: project.cameraKeyframes,
                    manualZoomSegments: project.manualZoomSegments
                )
                let pointerSnapshot = pointerTimeline.snapshot(at: timestamp, from: project.events, smoothing: .raw)

                if let buffer = makePixelBuffer(from: adaptor, size: size) {
                    drawDebugFrame(
                        in: buffer,
                        size: size,
                        snapshot: snapshot,
                        pointerSnapshot: pointerSnapshot,
                        project: project,
                        timestamp: timestamp
                    )
                    adaptor.append(buffer, withPresentationTime: presentationTime)
                }
            }
        }

        input.markAsFinished()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? VideoRendererError.writerFailed)
                }
            }
        }

        return destinationURL
    }

    private func renderSourceVideo(
        for project: RecordingProject,
        sourceURL: URL,
        renderSize: CGSize,
        destinationURL: URL
    ) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let preparedAssets = prepareAssets(renderSize: renderSize, style: project.style)

        let temporaryVideoURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent("render-\(UUID().uuidString).mp4")
        defer { try? fm.removeItem(at: temporaryVideoURL) }

        let renderedVideoURL: URL
        do {
            renderedVideoURL = try await renderFixedFrameVideo(
                for: project,
                sourceAsset: asset,
                preparedAssets: preparedAssets,
                renderSize: renderSize,
                destinationURL: temporaryVideoURL
            )
        } catch {
            throw normalizedRenderError(error, for: sourceURL)
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            try fm.moveItem(at: renderedVideoURL, to: destinationURL)
            return destinationURL
        }

        return try await muxAudio(
            from: asset,
            clipSegments: project.effectiveClipSegments,
            renderedVideoURL: renderedVideoURL,
            destinationURL: destinationURL
        )
    }

    private func renderFixedFrameVideo(
        for project: RecordingProject,
        sourceAsset: AVURLAsset,
        preparedAssets: PreparedRenderAssets,
        renderSize: CGSize,
        destinationURL: URL
    ) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height)
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw VideoRendererError.unableToCreateWriter
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let assetDuration = try await sourceAsset.load(.duration)
        let sourceDuration = max(CMTimeGetSeconds(assetDuration), 0)
        let clipSegments = RecordingProject.normalizedClipSegments(project.effectiveClipSegments, duration: sourceDuration)
        let safeDuration = max(totalDuration(of: clipSegments), 1.0 / Double(exportFPS))
        let totalFrames = max(Int(ceil(safeDuration * Double(exportFPS))), 1)
        let frameDuration = CMTime(value: 1, timescale: exportFPS)

        let generator = AVAssetImageGenerator(asset: sourceAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = renderSize
        // ScreenCaptureKit MP4s are not always seekable at exact frame timestamps.
        // A small tolerance keeps export aligned while avoiding decode/open failures.
        generator.requestedTimeToleranceBefore = sourceFrameSeekTolerance
        generator.requestedTimeToleranceAfter = sourceFrameSeekTolerance

        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()

            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            let outputTimestamp = min(Double(frameIndex) / Double(exportFPS), max(safeDuration - (1.0 / Double(exportFPS)), 0))
            let seconds = sourceTimestamp(atClipOffset: outputTimestamp, in: clipSegments)
            let sourceTime = CMTime(seconds: seconds, preferredTimescale: 600)
            let sourceFrame = try await generateSourceFrame(from: generator, at: sourceTime)
            try Task.checkCancellation()

            try autoreleasepool {
                let sourceImage = CIImage(cgImage: sourceFrame)
                let snapshot = composer.snapshot(
                    at: seconds,
                    from: project.cameraKeyframes,
                    manualZoomSegments: project.manualZoomSegments
                )
                let pointerSnapshot = pointerTimeline.snapshot(at: seconds, from: project.events, smoothing: .raw)
                let composedFrame = composeFrame(
                    from: sourceImage,
                    snapshot: snapshot,
                    pointerSnapshot: pointerSnapshot,
                    project: project,
                    preparedAssets: preparedAssets
                )

                guard let buffer = makePixelBuffer(from: adaptor, size: renderSize) else {
                    throw VideoRendererError.unableToCreatePixelBuffer
                }

                ciContext.render(
                    composedFrame.cropped(to: preparedAssets.layout.fullRect),
                    to: buffer,
                    bounds: preparedAssets.layout.fullRect,
                    colorSpace: renderColorSpace
                )

                guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                    throw writer.error ?? VideoRendererError.writerFailed
                }
            }
        }

        input.markAsFinished()
        try await finishWriting(writer)
        return destinationURL
    }

    private func generateSourceFrame(from generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, error in
                switch result {
                case .succeeded:
                    if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: VideoRendererError.unableToCreateContext)
                    }
                case .failed:
                    continuation.resume(throwing: error ?? VideoRendererError.legacySourceRequiresRecapture)
                case .cancelled:
                    continuation.resume(throwing: error ?? VideoRendererError.exportFailed)
                @unknown default:
                    continuation.resume(throwing: error ?? VideoRendererError.exportFailed)
                }
            }
        }
    }

    private func muxAudio(
        from sourceAsset: AVURLAsset,
        clipSegments: [ProjectTrimRange],
        renderedVideoURL: URL,
        destinationURL: URL
    ) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        let renderedAsset = AVURLAsset(url: renderedVideoURL)
        let composition = AVMutableComposition()

        guard
            let sourceVideoTrack = try await renderedAsset.loadTracks(withMediaType: .video).first,
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw VideoRendererError.exportFailed
        }

        let videoDuration = try await renderedAsset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let sourceAudioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        if !sourceAudioTracks.isEmpty {
            let sourceAudioDuration = try await sourceAsset.load(.duration)
            let sourceDuration = max(CMTimeGetSeconds(sourceAudioDuration), 0)
            let normalizedSegments = RecordingProject.normalizedClipSegments(clipSegments, duration: sourceDuration)

            for sourceAudioTrack in sourceAudioTracks {
                guard let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }

                var outputCursor = CMTime.zero
                for segment in normalizedSegments {
                    let audioStart = CMTime(seconds: segment.start, preferredTimescale: 600)
                    let requestedDuration = CMTime(seconds: segment.duration, preferredTimescale: 600)
                    let remainingSourceDuration = CMTimeSubtract(sourceAudioDuration, audioStart)
                    let remainingOutputDuration = CMTimeSubtract(videoDuration, outputCursor)
                    let audioDuration = CMTimeMinimum(
                        requestedDuration,
                        CMTimeMinimum(remainingSourceDuration, remainingOutputDuration)
                    )

                    guard CMTimeCompare(audioDuration, .zero) > 0 else { continue }

                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: audioStart, duration: audioDuration),
                        of: sourceAudioTrack,
                        at: outputCursor
                    )
                    outputCursor = CMTimeAdd(outputCursor, audioDuration)
                }

                let inputParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                inputParameters.setVolume(1.0, at: .zero)
                audioMixParameters.append(inputParameters)
            }
        }

        // ScreenCaptureKit system-audio tracks are not consistently mp4-compatible
        // when passed through directly. Re-encoding keeps single-track exports
        // stable instead of failing only when the source happens to contain a
        // non-passthrough-friendly audio format.
        let exportPreset = AVAssetExportPresetHighestQuality

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: exportPreset) else {
            throw VideoRendererError.unableToCreateExportSession
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        if sourceAudioTracks.count > 1, audioMixParameters.isEmpty == false {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exportSession.audioMix = audioMix
        }

        try await export(exportSession)
        return destinationURL
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? VideoRendererError.writerFailed)
                }
            }
        }
    }

    private func totalDuration(of clipSegments: [ProjectTrimRange]) -> TimeInterval {
        clipSegments.reduce(0) { $0 + $1.duration }
    }

    private func sourceTimestamp(atClipOffset offset: TimeInterval, in clipSegments: [ProjectTrimRange]) -> TimeInterval {
        guard let first = clipSegments.first else { return 0 }

        var remaining = offset.clamped(to: 0...max(totalDuration(of: clipSegments), 0))
        for segment in clipSegments {
            if remaining <= segment.duration {
                return segment.start + remaining
            }
            remaining -= segment.duration
        }

        return clipSegments.last?.end ?? first.start
    }

    private func normalizedRenderError(_ error: Error, for sourceURL: URL) -> Error {
        guard sourceURL.pathExtension.lowercased() == "mp4" else {
            return error
        }

        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let avCodes: Set<Int> = [-11800, -11821, -11832, -11869]
        let osStatusCodes: Set<Int> = [-12911, -12431, -12430, -12122]

        if avCodes.contains(nsError.code) || osStatusCodes.contains(nsError.code) {
            return VideoRendererError.legacySourceRequiresRecapture
        }

        if let underlyingError, osStatusCodes.contains(underlyingError.code) {
            return VideoRendererError.legacySourceRequiresRecapture
        }

        return error
    }

    private func export(_ session: AVAssetExportSession) async throws {
        let exportSessionBox = ExportSessionBox(session: session)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSessionBox.session.exportAsynchronously {
                switch exportSessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSessionBox.session.error ?? VideoRendererError.exportFailed)
                default:
                    continuation.resume(throwing: VideoRendererError.exportFailed)
                }
            }
        }
    }

    private func previewRenderSize(for renderSize: CGSize) -> CGSize {
        let longestSide = max(renderSize.width, renderSize.height)
        guard longestSide > previewLongestSide else { return renderSize }

        let scale = previewLongestSide / longestSide
        return CGSize(
            width: floor(renderSize.width * scale),
            height: floor(renderSize.height * scale)
        )
    }

    private func previewVideoRenderSize(for renderSize: CGSize) -> CGSize {
        let longestSide = max(renderSize.width, renderSize.height)
        guard longestSide > previewVideoLongestSide else { return renderSize }

        let scale = previewVideoLongestSide / longestSide
        return CGSize(
            width: floor(renderSize.width * scale),
            height: floor(renderSize.height * scale)
        )
    }

    private func prepareAssets(renderSize: CGSize, style: ProjectStyle) -> PreparedRenderAssets {
        let layout = RenderLayout(renderSize: renderSize, padding: style.padding)
        return PreparedRenderAssets(
            layout: layout,
            backgroundImage: makeBackgroundImage(
                size: layout.renderSize,
                style: style.background,
                contentRect: layout.contentRect,
                cornerRadius: style.cornerRadius,
                shadowRadius: style.shadowRadius
            ),
            transparentCanvas: CIImage(color: .clear).cropped(to: layout.fullRect),
            maskImage: makeRoundedMaskImage(
                size: layout.renderSize,
                contentRect: layout.contentRect,
                cornerRadius: style.cornerRadius
            )
        )
    }

    private func composeFrame(
        from sourceImage: CIImage,
        snapshot: FrameSnapshot,
        pointerSnapshot: PointerSnapshot?,
        project: RecordingProject,
        preparedAssets: PreparedRenderAssets
    ) -> CIImage {
        let cropRect = cropPlanner.cropRect(
            for: sourceImage.extent,
            outputAspectRatio: preparedAssets.layout.outputAspectRatio,
            snapshot: snapshot
        )

        let translated = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))

        let scaleX = preparedAssets.layout.contentRect.width / cropRect.width
        let scaleY = preparedAssets.layout.contentRect.height / cropRect.height

        let positioned = translated
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(
                by: CGAffineTransform(
                    translationX: preparedAssets.layout.contentRect.minX,
                    y: preparedAssets.layout.contentRect.minY
                )
            )

        let contentOnCanvas = positioned.composited(over: preparedAssets.transparentCanvas)
        let maskedContent = contentOnCanvas.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: preparedAssets.transparentCanvas,
                kCIInputMaskImageKey: preparedAssets.maskImage
            ]
        )

        let emphasized = applyClickEmphasis(
            to: maskedContent,
            snapshot: snapshot,
            reconstructsCursor: project.reconstructsCursor,
            layout: preparedAssets.layout,
            sourceExtent: sourceImage.extent,
            cropRect: cropRect
        )

        let withCursor = applyCursorOverlay(
            to: emphasized,
            pointerSnapshot: pointerSnapshot,
            reconstructsCursor: project.reconstructsCursor,
            layout: preparedAssets.layout,
            sourceExtent: sourceImage.extent,
            cropRect: cropRect
        )

        return withCursor.composited(over: preparedAssets.backgroundImage)
    }

    private func makeBackgroundImage(
        size: CGSize,
        style: ProjectBackgroundStyle,
        contentRect: CGRect,
        cornerRadius: Double = 26,
        shadowRadius: Double = 30
    ) -> CIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        let colors: [CGColor]
        switch style {
        case .aurora:
            colors = [
                CGColor(red: 0.88, green: 0.95, blue: 1.0, alpha: 1),
                CGColor(red: 0.86, green: 0.98, blue: 0.90, alpha: 1),
                CGColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 1)
            ]
        case .graphite:
            colors = [
                CGColor(red: 0.15, green: 0.17, blue: 0.24, alpha: 1),
                CGColor(red: 0.22, green: 0.24, blue: 0.34, alpha: 1),
                CGColor(red: 0.16, green: 0.21, blue: 0.29, alpha: 1)
            ]
        case .sunrise:
            colors = [
                CGColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1),
                CGColor(red: 1.0, green: 0.83, blue: 0.78, alpha: 1),
                CGColor(red: 0.99, green: 0.88, blue: 0.95, alpha: 1)
            ]
        case .ocean:
            colors = [
                CGColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 1),
                CGColor(red: 0.48, green: 0.72, blue: 0.98, alpha: 1),
                CGColor(red: 0.18, green: 0.34, blue: 0.72, alpha: 1)
            ]
        case .plum:
            colors = [
                CGColor(red: 0.95, green: 0.84, blue: 1.0, alpha: 1),
                CGColor(red: 0.68, green: 0.56, blue: 0.94, alpha: 1),
                CGColor(red: 0.30, green: 0.20, blue: 0.48, alpha: 1)
            ]
        case .moss:
            colors = [
                CGColor(red: 0.88, green: 0.96, blue: 0.78, alpha: 1),
                CGColor(red: 0.62, green: 0.76, blue: 0.52, alpha: 1),
                CGColor(red: 0.24, green: 0.38, blue: 0.30, alpha: 1)
            ]
        case .paper:
            colors = [
                CGColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
                CGColor(red: 0.90, green: 0.91, blue: 0.92, alpha: 1),
                CGColor(red: 0.78, green: 0.84, blue: 0.88, alpha: 1)
            ]
        case .midnight:
            colors = [
                CGColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1),
                CGColor(red: 0.09, green: 0.12, blue: 0.22, alpha: 1),
                CGColor(red: 0.14, green: 0.20, blue: 0.35, alpha: 1)
            ]
        }

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }

        guard let image = context.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }
        return CIImage(cgImage: image)
    }

    private func makeRoundedMaskImage(size: CGSize, contentRect: CGRect, cornerRadius: Double) -> CIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let path = CGPath(
            roundedRect: contentRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()

        guard let image = context.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        return CIImage(cgImage: image)
    }

    private func applyClickEmphasis(
        to image: CIImage,
        snapshot: FrameSnapshot,
        reconstructsCursor: Bool,
        layout: RenderLayout,
        sourceExtent: CGRect,
        cropRect: CGRect
    ) -> CIImage {
        guard reconstructsCursor == false else {
            return image
        }

        guard snapshot.emphasis == .click else {
            return image
        }

        let point = cropPlanner.mappedContentPoint(
            for: snapshot.focus,
            in: sourceExtent,
            cropRect: cropRect,
            layout: layout
        )
        return applyClickRipple(to: image, point: point, intensity: 1.0, layout: layout)
    }

    private func applyClickRipple(
        to image: CIImage,
        point: CGPoint,
        intensity: Double,
        layout: RenderLayout
    ) -> CIImage {
        let radius = max(20, min(layout.contentRect.width, layout.contentRect.height) * (0.034 + (0.016 * intensity)))

        let solidCircle = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.14))
            .cropped(to: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            .applyingFilter(
                "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: point.x, y: point.y),
                    "inputRadius0": radius * 0.15,
                    "inputRadius1": radius,
                    "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.08 + (0.08 * intensity)),
                    "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)
                ]
            )
            .cropped(to: layout.fullRect)

        let ring = CIImage(color: .clear)
            .cropped(to: layout.fullRect)
            .applyingFilter(
                "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: point.x, y: point.y),
                    "inputRadius0": radius * 0.82,
                    "inputRadius1": radius * 1.08,
                    "inputColor0": CIColor(red: 0.15, green: 0.47, blue: 1.0, alpha: 0.22 + (0.18 * intensity)),
                    "inputColor1": CIColor(red: 0.15, green: 0.47, blue: 1.0, alpha: 0)
                ]
            )
            .cropped(to: layout.fullRect)

        return ring.composited(over: solidCircle.composited(over: image))
    }

    private func applyCursorOverlay(
        to image: CIImage,
        pointerSnapshot: PointerSnapshot?,
        reconstructsCursor: Bool,
        layout: RenderLayout,
        sourceExtent: CGRect,
        cropRect: CGRect
    ) -> CIImage {
        guard reconstructsCursor, let pointerSnapshot else { return image }

        let point = cropPlanner.mappedContentPoint(
            for: pointerSnapshot.location,
            in: sourceExtent,
            cropRect: cropRect,
            layout: layout
        )

        var layeredImage = image
        if pointerSnapshot.isClickActive, let clickLocation = pointerSnapshot.clickLocation {
            let clickPoint = cropPlanner.mappedContentPoint(
                for: clickLocation,
                in: sourceExtent,
                cropRect: cropRect,
                layout: layout
            )
            let intensity = (0.45 + (pointerSnapshot.clickProgress * 0.55)).clamped(to: 0.45...1.0)
            layeredImage = applyClickRipple(to: layeredImage, point: clickPoint, intensity: intensity, layout: layout)
        }

        let baseScale = (min(layout.contentRect.width, layout.contentRect.height) / 1050).clamped(to: 0.78...1.08)
        let scale = baseScale * (1 + (pointerSnapshot.clickProgress * 0.05))
        let origin = CursorGeometry.origin(forTip: point, scale: scale)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: origin.x, y: origin.y)

        let cursor = cursorTemplateImage
            .transformed(by: transform)
            .cropped(to: layout.fullRect)

        return cursor.composited(over: layeredImage)
    }

    private func makePixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor, size: CGSize) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess else { return nil }
        return buffer
    }

    private func makeCursorTemplateImage() -> CIImage {
        let size = CursorGeometry.templateSize
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
        }

        context.clear(CGRect(origin: .zero, size: size))

        let cursorPath = CGMutablePath()
        cursorPath.move(to: CGPoint(x: 5, y: 5))
        cursorPath.addLine(to: CGPoint(x: 5, y: 35))
        cursorPath.addLine(to: CGPoint(x: 13, y: 27))
        cursorPath.addLine(to: CGPoint(x: 18, y: 40))
        cursorPath.addLine(to: CGPoint(x: 24, y: 37))
        cursorPath.addLine(to: CGPoint(x: 19, y: 25))
        cursorPath.addLine(to: CGPoint(x: 31, y: 25))
        cursorPath.closeSubpath()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
        context.addPath(cursorPath)
        context.fillPath()
        context.restoreGState()

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(cursorPath)
        context.fillPath()

        context.setStrokeColor(CGColor(red: 0.02, green: 0.025, blue: 0.035, alpha: 0.90))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineWidth(1.35)
        context.addPath(cursorPath)
        context.strokePath()

        guard let image = context.makeImage() else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
        }

        return CIImage(cgImage: image)
    }

    private func drawDebugFrame(
        in buffer: CVPixelBuffer,
        size: CGSize,
        snapshot: FrameSnapshot,
        pointerSnapshot: PointerSnapshot?,
        project: RecordingProject,
        timestamp: TimeInterval
    ) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard
            let base = CVPixelBufferGetBaseAddress(buffer),
            let context = CGContext(
                data: base,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
        else {
            return
        }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        drawDebugBackground(in: context, size: size, style: project.style.background)

        let padding = project.style.padding * min(size.width, size.height)
        let contentRect = CGRect(
            x: padding,
            y: padding,
            width: size.width - (padding * 2),
            height: size.height - (padding * 2)
        )

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
        let cardPath = CGPath(
            roundedRect: contentRect,
            cornerWidth: project.style.cornerRadius,
            cornerHeight: project.style.cornerRadius,
            transform: nil
        )
        context.addPath(cardPath)
        context.fillPath()

        drawDebugGrid(in: context, rect: contentRect)

        let focusSource = project.reconstructsCursor ? (pointerSnapshot?.location ?? snapshot.focus) : snapshot.focus
        let focusPoint = CGPoint(
            x: contentRect.minX + (focusSource.x * contentRect.width),
            y: contentRect.minY + (focusSource.y * contentRect.height)
        )

        let ringRadius = 42 * snapshot.zoom
        context.setStrokeColor(CGColor(red: 0.10, green: 0.42, blue: 0.96, alpha: 0.24))
        context.setLineWidth(10)
        context.strokeEllipse(in: CGRect(
            x: focusPoint.x - ringRadius,
            y: focusPoint.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))

        context.setFillColor(CGColor(red: 0.10, green: 0.42, blue: 0.96, alpha: 1.0))
        context.fillEllipse(in: CGRect(x: focusPoint.x - 10, y: focusPoint.y - 10, width: 20, height: 20))

        context.setFillColor(CGColor(gray: 0.15, alpha: 0.08))
        let pulse = 14 + (sin(timestamp * 6) * 6)
        context.fillEllipse(in: CGRect(
            x: focusPoint.x - 10 - pulse,
            y: focusPoint.y - 10 - pulse,
            width: 20 + (pulse * 2),
            height: 20 + (pulse * 2)
        ))
    }

    private func drawDebugBackground(in context: CGContext, size: CGSize, style: ProjectBackgroundStyle) {
        let background = makeBackgroundImage(
            size: size,
            style: style,
            contentRect: CGRect(origin: .zero, size: size)
        )
        ciContext.draw(background, in: CGRect(origin: .zero, size: size), from: CGRect(origin: .zero, size: size))
    }

    private func drawDebugGrid(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.82, alpha: 0.6))
        context.setLineWidth(1)

        let columns = 4
        let rows = 3

        for column in 1..<columns {
            let x = rect.minX + (rect.width / CGFloat(columns)) * CGFloat(column)
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        for row in 1..<rows {
            let y = rect.minY + (rect.height / CGFloat(rows)) * CGFloat(row)
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        context.strokePath()
        context.restoreGState()
    }
}

private struct UIEdgeInsetsLike {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat
}

private extension CGRect {
    func inset(by insets: UIEdgeInsetsLike) -> CGRect {
        CGRect(
            x: minX + insets.left,
            y: minY + insets.bottom,
            width: width - insets.left - insets.right,
            height: height - insets.top - insets.bottom
        )
    }
}

final class ExportCoordinator {
    private let renderer: VideoRenderer
    private let projectStore: ProjectStore

    init(renderer: VideoRenderer, projectStore: ProjectStore) {
        self.renderer = renderer
        self.projectStore = projectStore
    }

    func exportVideo(for project: RecordingProject, preset: ExportPreset) async throws -> URL {
        let exportDirectory = projectStore.exportDirectory(for: project)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true, attributes: nil)
        let filename = Self.exportFilename(for: project, preset: preset)
        let destinationURL = exportDirectory.appendingPathComponent(filename)
        return try await exportVideo(for: project, preset: preset, destinationURL: destinationURL)
    }

    func exportVideo(for project: RecordingProject, preset: ExportPreset, destinationURL: URL) async throws -> URL {
        let workingDirectory = projectStore.exportDirectory(for: project)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true, attributes: nil)

        let workingURL = workingDirectory.appendingPathComponent("working-\(UUID().uuidString).mp4")
        defer {
            if workingURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: workingURL)
            }
        }

        let renderedURL = try await renderer.renderVideo(for: project, preset: preset, destinationURL: workingURL)
        return try moveExportedVideo(from: renderedURL, to: destinationURL)
    }

    private func moveExportedVideo(from sourceURL: URL, to destinationURL: URL) throws -> URL {
        let fileManager = FileManager.default
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            return sourceURL
        }

        let accessedSecurityScope = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func exportFilename(for project: RecordingProject, preset: ExportPreset) -> String {
        let stamp = project.createdAt.formatted(
            .dateTime
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
        let normalizedStamp = stamp
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return "\(project.name.filenameSlug)-\(normalizedStamp)-\(preset.rawValue).mp4"
    }
}

private extension String {
    var filenameSlug: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let joined = pieces.joined(separator: "_")
        return joined.isEmpty ? "MouseLens_Export" : joined
    }
}

private extension NormalizedPoint {
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
