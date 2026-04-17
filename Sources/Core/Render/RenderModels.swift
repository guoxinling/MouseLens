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

protocol ProjectPreviewRendering {
    @MainActor
    func makePreviewImage(
        for project: RecordingProject,
        preset: ExportPreset,
        timestamp: TimeInterval
    ) async throws -> NSImage?
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
}

struct SourceCropPlanner {
    func cropRect(
        for sourceExtent: CGRect,
        outputAspectRatio: CGFloat,
        snapshot: FrameSnapshot
    ) -> CGRect {
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return sourceExtent }

        let baseCrop = baseCropRect(for: sourceExtent, outputAspectRatio: outputAspectRatio)
        let zoom = snapshot.zoom.clamped(to: 1.0...1.8)
        let cropWidth = baseCrop.width / zoom
        let cropHeight = baseCrop.height / zoom

        let safeInsets = recommendedSafeInsets(for: sourceExtent)
        let safeRect = sourceExtent.insetBy(dx: safeInsets.dx, dy: 0)
            .inset(by: UIEdgeInsetsLike(top: safeInsets.top, left: 0, bottom: safeInsets.bottom, right: 0))

        let centerX = safeRect.minX + (snapshot.focus.x * safeRect.width)
        let centerY = safeRect.maxY - (snapshot.focus.y * safeRect.height)

        let minX = sourceExtent.minX
        let maxX = sourceExtent.maxX - cropWidth
        let minY = sourceExtent.minY
        let maxY = sourceExtent.maxY - cropHeight

        let originX = (centerX - (cropWidth / 2)).clamped(to: minX...max(maxX, minX))
        let originY = (centerY - (cropHeight / 2)).clamped(to: minY...max(maxY, minY))

        return CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
    }

    private func recommendedSafeInsets(for sourceExtent: CGRect) -> (dx: CGFloat, top: CGFloat, bottom: CGFloat) {
        let horizontalInset = sourceExtent.width * 0.02
        let topInset = sourceExtent.height * 0.035
        let bottomInset = sourceExtent.height * 0.10
        return (horizontalInset, topInset, bottomInset)
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
}

struct RenderLayout {
    let renderSize: CGSize
    let fullRect: CGRect
    let contentRect: CGRect

    init(renderSize: CGSize, padding: Double) {
        self.renderSize = renderSize
        fullRect = CGRect(origin: .zero, size: renderSize)

        let inset = max(renderSize.width, renderSize.height) > 0
            ? padding * min(renderSize.width, renderSize.height)
            : 0
        contentRect = CGRect(
            x: inset,
            y: inset,
            width: max(renderSize.width - (inset * 2), 1),
            height: max(renderSize.height - (inset * 2), 1)
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
    private let cropPlanner = SourceCropPlanner()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let previewLongestSide: CGFloat = 1280
    private let exportFPS: Int32 = 30
    private let renderColorSpace = CGColorSpaceCreateDeviceRGB()

    func renderVideo(for project: RecordingProject, preset: ExportPreset, destinationURL: URL) async throws -> URL {
        guard let sourceURL = project.sourceVideoURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            return try await renderDebugVideo(for: project, preset: preset, destinationURL: destinationURL)
        }

        return try await renderSourceVideo(
            for: project,
            preset: preset,
            sourceURL: sourceURL,
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
        let clampedTimestamp = timestamp.clamped(to: 0...max(project.duration, 0))
        let snapshot = composer.snapshot(at: clampedTimestamp, from: project.cameraKeyframes)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let asset = AVURLAsset(url: sourceURL)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = renderSize

                    let time = CMTime(seconds: clampedTimestamp, preferredTimescale: 600)
                    let sourceFrame = try generator.copyCGImage(at: time, actualTime: nil)
                    let sourceImage = CIImage(cgImage: sourceFrame)
                    let preparedAssets = prepareAssets(renderSize: renderSize, style: project.style)
                    let composedFrame = composeFrame(
                        from: sourceImage,
                        snapshot: snapshot,
                        preparedAssets: preparedAssets
                    )

                    guard let outputImage = ciContext.createCGImage(composedFrame, from: preparedAssets.layout.fullRect) else {
                        throw VideoRendererError.unableToCreateContext
                    }

                    continuation.resume(returning: NSImage(cgImage: outputImage, size: renderSize))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func renderDebugVideo(for project: RecordingProject, preset: ExportPreset, destinationURL: URL) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        let size = preset.renderSize
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
        let duration = max(project.duration, 6.0)
        let totalFrames = max(Int(duration * Double(fps)), 1)
        let frameDuration = CMTime(value: 1, timescale: fps)

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            autoreleasepool {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                let timestamp = Double(frameIndex) / Double(fps)
                let snapshot = composer.snapshot(at: timestamp, from: project.cameraKeyframes)

                if let buffer = makePixelBuffer(from: adaptor, size: size) {
                    drawDebugFrame(
                        in: buffer,
                        size: size,
                        snapshot: snapshot,
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
        preset: ExportPreset,
        sourceURL: URL,
        destinationURL: URL
    ) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let renderSize = preset.renderSize
        let preparedAssets = prepareAssets(renderSize: renderSize, style: project.style)

        let temporaryVideoURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent("render-\(UUID().uuidString).mp4")
        defer { try? fm.removeItem(at: temporaryVideoURL) }

        let renderedVideoURL = try await renderFixedFrameVideo(
            for: project,
            sourceAsset: asset,
            preparedAssets: preparedAssets,
            renderSize: renderSize,
            destinationURL: temporaryVideoURL
        )

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            try fm.moveItem(at: renderedVideoURL, to: destinationURL)
            return destinationURL
        }

        return try await muxAudio(
            from: asset,
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
        let durationSeconds = max(project.duration, CMTimeGetSeconds(assetDuration))
        let safeDuration = max(durationSeconds, 1.0 / Double(exportFPS))
        let totalFrames = max(Int(ceil(safeDuration * Double(exportFPS))), 1)
        let frameDuration = CMTime(value: 1, timescale: exportFPS)
        let maxTimestamp = max(safeDuration - (1.0 / Double(exportFPS)), 0)

        let generator = AVAssetImageGenerator(asset: sourceAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = renderSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            try autoreleasepool {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                let seconds = min(Double(frameIndex) / Double(exportFPS), maxTimestamp)
                let sourceTime = CMTime(seconds: seconds, preferredTimescale: 600)
                let sourceFrame = try generator.copyCGImage(at: sourceTime, actualTime: nil)
                let sourceImage = CIImage(cgImage: sourceFrame)
                let snapshot = composer.snapshot(at: seconds, from: project.cameraKeyframes)
                let composedFrame = composeFrame(
                    from: sourceImage,
                    snapshot: snapshot,
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

    private func muxAudio(
        from sourceAsset: AVURLAsset,
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

        if
            let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first,
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        {
            let sourceAudioDuration = try await sourceAsset.load(.duration)
            let audioDuration = CMTimeMinimum(videoDuration, sourceAudioDuration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoRendererError.unableToCreateExportSession
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

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
            layout: preparedAssets.layout
        )

        return emphasized.composited(over: preparedAssets.backgroundImage)
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
        }

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }

        let shadowRect = contentRect.offsetBy(dx: 0, dy: -10)
        let shadowPath = CGPath(
            roundedRect: shadowRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
        context.setShadow(offset: CGSize(width: 0, height: 14), blur: shadowRadius, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
        context.addPath(shadowPath)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

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
        layout: RenderLayout
    ) -> CIImage {
        guard snapshot.emphasis == .click else { return image }

        let point = CGPoint(
            x: layout.contentRect.minX + (snapshot.focus.x * layout.contentRect.width),
            y: layout.contentRect.minY + ((1 - snapshot.focus.y) * layout.contentRect.height)
        )
        let radius = max(28, min(layout.contentRect.width, layout.contentRect.height) * 0.06)

        let solidCircle = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.14))
            .cropped(to: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            .applyingFilter(
                "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: point.x, y: point.y),
                    "inputRadius0": radius * 0.15,
                    "inputRadius1": radius,
                    "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.24),
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
                    "inputRadius0": radius * 0.78,
                    "inputRadius1": radius * 1.05,
                    "inputColor0": CIColor(red: 0.15, green: 0.47, blue: 1.0, alpha: 0.65),
                    "inputColor1": CIColor(red: 0.15, green: 0.47, blue: 1.0, alpha: 0)
                ]
            )
            .cropped(to: layout.fullRect)

        return ring.composited(over: solidCircle.composited(over: image))
    }

    private func makePixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor, size: CGSize) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess else { return nil }
        return buffer
    }

    private func drawDebugFrame(
        in buffer: CVPixelBuffer,
        size: CGSize,
        snapshot: FrameSnapshot,
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

        let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.18)
        context.setShadow(offset: CGSize(width: 0, height: 14), blur: project.style.shadowRadius, color: shadowColor)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
        let cardPath = CGPath(
            roundedRect: contentRect,
            cornerWidth: project.style.cornerRadius,
            cornerHeight: project.style.cornerRadius,
            transform: nil
        )
        context.addPath(cardPath)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        drawDebugGrid(in: context, rect: contentRect)

        let focusPoint = CGPoint(
            x: contentRect.minX + (snapshot.focus.x * contentRect.width),
            y: contentRect.minY + (snapshot.focus.y * contentRect.height)
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
        return try await renderer.renderVideo(for: project, preset: preset, destinationURL: destinationURL)
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
