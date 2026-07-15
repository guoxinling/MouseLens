import AppKit
import AVFoundation
import AVKit
import SwiftUI

struct PreviewPlaybackTimeline {
    let project: RecordingProject
    let displayDuration: TimeInterval
    let usesSourceTimeline: Bool

    func displayTime(forPlaybackTime playbackTime: TimeInterval) -> TimeInterval {
        if usesSourceTimeline {
            return project.clipOffset(forSourceTimestamp: playbackTime)
                .clamped(to: 0...displayDuration)
        }

        return playbackTime.clamped(to: 0...displayDuration)
    }

    func sourceTime(forDisplayTime displayTime: TimeInterval) -> TimeInterval {
        let clampedTime = displayTime.clamped(to: 0...displayDuration)
        if usesSourceTimeline {
            return project.sourceTimestamp(forClipOffset: clampedTime)
        }

        return clampedTime
    }
}

struct PreviewCanvasView: View {
    let project: RecordingProject
    let previewImage: NSImage?
    let isPreviewLoading: Bool
    let previewVideoURL: URL?
    let previewVideoState: PreviewVideoState
    let prefersStaticPreview: Bool
    let showsPlayablePreview: Bool
    let trimRange: ProjectTrimRange
    let previewDuration: TimeInterval
    @Binding var previewTimestamp: TimeInterval
    let onPlaybackTimeChange: (TimeInterval) -> Void
    let onPlaybackEnded: () -> Void
    let onRefreshPreviewVideo: () -> Void
    let selectedManualZoomSegment: ManualZoomSegment?
    let onManualZoomFocusChange: (NormalizedPoint) -> Void
    @State private var isHoveringPreviewStage = false
    @State private var hasActivatedPlayback = false
    @State private var sourceVideoSize: CGSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewStage

            previewControls
        }
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(previewTitle, systemImage: previewIconName)
                Text(previewTimingLabel)
                    .foregroundStyle(AppTheme.mutedText)
                Spacer()
                if previewVideoState.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    onRefreshPreviewVideo()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh preview")
                .disabled(previewVideoState.isWorking || project.sourceVideoURL == nil)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            if case .failed(let message) = previewVideoState {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var previewStage: some View {
        let canvasAspectRatio = project.style.aspectRatio.canvasAspectRatio
        let showsLoadingOverlay = shouldShowLoadingOverlay

        return ZStack {
            BackgroundPreviewFill(preset: project.style.backgroundPreset)
                .opacity(0.88)

            if usesLiveStylePlayback, let activePlaybackURL {
                liveStylePlaybackStage(url: activePlaybackURL)
            } else if shouldShowPlayer, let activePlaybackURL {
                PreviewVideoPlayerView(
                    url: activePlaybackURL,
                    seekTime: activePlaybackSeekTime,
                    displayTime: previewTimestamp.clamped(to: 0...previewDuration),
                    playbackTimeline: playbackTimeline,
                    onDisplaySeekRequested: { displayTime in
                        onPlaybackTimeChange(displayTime.clamped(to: 0...previewDuration))
                    },
                    onPlaybackTimeChange: { playbackTime in
                        updateTimelineFromPlayback(
                            playbackTime,
                            usesSourceTimeline: activePlaybackUsesSourceTimeline
                        )
                    },
                    onPlaybackEnded: {
                        onPlaybackEnded()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shouldPreferStaticPreview, let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                GeometryReader { geometry in
                    fallbackPreview(in: geometry.size)
                }
            }

            if showsLoadingOverlay {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.large)
                    Text(previewVideoState == .updating ? "Updating preview" : "Preparing preview")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(canvasAspectRatio, contentMode: .fit)
        .clipped()
        .onHover {
            isHoveringPreviewStage = $0
            if $0 {
                hasActivatedPlayback = true
            }
        }
        .task(id: project.sourceVideoURL) {
            sourceVideoSize = await loadSourceVideoDisplaySize(from: project.sourceVideoURL)
        }
        .layoutPriority(1)
    }

    private func liveStylePlaybackStage(url: URL) -> some View {
        GeometryReader { geometry in
            let stageSize = geometry.size
            let renderLayout = RenderLayout(renderSize: stageSize, padding: project.style.padding)
            let contentRect = renderLayout.contentRect
            let sourceSize = sourceVideoSize ?? CGSize(width: 1920, height: 1080)
            let sourceTimestamp = project.sourceTimestamp(forClipOffset: previewTimestamp)
            let frameSnapshot = FrameComposer().snapshot(
                at: sourceTimestamp,
                from: project.cameraKeyframes,
                manualZoomSegments: project.manualZoomSegments,
                zoomTrackEdited: project.zoomTrackEdited
            )
            let pointerSnapshot = PointerTimeline().snapshot(at: sourceTimestamp, from: project.events, smoothing: .raw)
            let previewGeometry = RealtimePreviewGeometry(
                sourceSize: sourceSize,
                contentRect: contentRect,
                snapshot: frameSnapshot,
                preservesFullSourceAtBase: project.captureTarget == .window
            )
            let presenterStyle = project.style.presenterBubbleStyle
            let presenterLayout = PresenterOverlayGeometry.layout(
                contentRect: contentRect,
                style: presenterStyle
            )
            let presenterVideoURL = presenterStyle.isEnabled ? project.presenterMedia?.sourceVideoURL : nil
            let cornerRadius = max(project.style.cornerRadius, 0)

            ZStack {
                BackgroundPreviewFill(preset: project.style.backgroundPreset)

                ZStack(alignment: .topLeading) {
                    PreviewVideoPlayerView(
                        url: url,
                        seekTime: activePlaybackSeekTime,
                        displayTime: previewTimestamp.clamped(to: 0...previewDuration),
                        playbackTimeline: playbackTimeline,
                        pointerSnapshot: pointerSnapshot,
                        frameSnapshot: frameSnapshot,
                        realtimeGeometry: previewGeometry,
                        contentCornerRadius: cornerRadius,
                        showsReconstructedCursor: project.reconstructsCursor,
                        presenterVideoURL: presenterVideoURL,
                        presenterSeekTime: max(sourceTimestamp + (project.presenterMedia?.renderOffset ?? 0), 0),
                        presenterLayout: presenterLayout.frame.isEmpty ? nil : presenterLayout,
                        presenterShadowOpacity: presenterStyle.shadowOpacity,
                        onDisplaySeekRequested: { displayTime in
                            onPlaybackTimeChange(displayTime.clamped(to: 0...previewDuration))
                        },
                        onPlaybackTimeChange: { playbackTime in
                            updateTimelineFromPlayback(playbackTime, usesSourceTimeline: true)
                        },
                        onPlaybackEnded: {
                            onPlaybackEnded()
                        }
                    )
                    .frame(width: stageSize.width, height: stageSize.height)
                    .position(x: stageSize.width / 2, y: stageSize.height / 2)

                    if let selectedManualZoomSegment {
                        ManualZoomFocusOverlay(
                            segment: selectedManualZoomSegment,
                            onFocusChange: onManualZoomFocusChange
                        )
                        .frame(width: contentRect.width, height: contentRect.height)
                        .position(x: contentRect.midX, y: contentRect.midY)
                        .zIndex(20)
                    }
                }
                .frame(width: stageSize.width, height: stageSize.height)

                if project.reconstructsCursor && project.events.isEmpty {
                    Text("No pointer events captured")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.36), in: Capsule())
                        .position(x: contentRect.midX, y: contentRect.maxY - 20)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var activePlaybackURL: URL? {
        project.sourceVideoURL
    }

    private var activePlaybackSeekTime: TimeInterval {
        playbackTimeline.sourceTime(forDisplayTime: previewTimestamp)
    }

    private var activePlaybackUsesSourceTimeline: Bool {
        true
    }

    private var playbackTimeline: PreviewPlaybackTimeline {
        PreviewPlaybackTimeline(
            project: project,
            displayDuration: previewDuration,
            usesSourceTimeline: activePlaybackUsesSourceTimeline
        )
    }

    private func updateTimelineFromPlayback(_ playbackTime: TimeInterval, usesSourceTimeline: Bool) {
        let clipOffset = PreviewPlaybackTimeline(
            project: project,
            displayDuration: previewDuration,
            usesSourceTimeline: usesSourceTimeline
        )
        .displayTime(forPlaybackTime: playbackTime)
        onPlaybackTimeChange(clipOffset)
    }

    private var usesLiveStylePlayback: Bool {
        guard showsPlayablePreview, project.sourceVideoURL != nil else { return false }
        return true
    }

    private var shouldShowPlayer: Bool {
        guard showsPlayablePreview, activePlaybackURL != nil else { return false }
        return usesLiveStylePlayback || hasActivatedPlayback || !shouldPreferStaticPreview || isHoveringPreviewStage
    }

    private var shouldPreferStaticPreview: Bool {
        guard !usesLiveStylePlayback else { return false }
        guard previewImage != nil else { return false }
        guard !hasActivatedPlayback else { return false }
        guard !isHoveringPreviewStage else { return false }
        return !showsPlayablePreview || activePlaybackURL == nil
    }

    private var shouldShowLoadingOverlay: Bool {
        if showsPlayablePreview, activePlaybackURL != nil {
            return previewVideoState == .rendering && previewImage == nil && !shouldShowPlayer && !usesLiveStylePlayback
        }

        return isPreviewLoading && previewImage == nil
    }

    private func fallbackPreview(in size: CGSize) -> some View {
        ZStack {
            BackgroundPreviewFill(preset: project.style.backgroundPreset)

            RoundedRectangle(cornerRadius: project.style.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .padding(size.width * project.style.padding)

            ForEach(project.cameraKeyframes.prefix(10)) { frame in
                Circle()
                    .fill(AppTheme.accent.opacity(0.18))
                    .frame(width: 36 * frame.zoom, height: 36 * frame.zoom)
                    .position(
                        x: frame.focus.cgPoint.x * size.width,
                        y: frame.focus.cgPoint.y * size.height
                    )
            }

            if let last = project.cameraKeyframes.last {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                    .position(
                        x: last.focus.cgPoint.x * size.width,
                        y: last.focus.cgPoint.y * size.height
                    )
            }
        }
    }

    private var previewTitle: String {
        if activePlaybackURL != nil && showsPlayablePreview {
            return "Playable Preview"
        }

        return previewImage == nil ? "Motion Preview" : "Frame Preview"
    }

    private var previewIconName: String {
        if activePlaybackURL != nil && showsPlayablePreview {
            return "play.rectangle"
        }

        return previewImage == nil ? "scope" : "photo"
    }

    private var previewTimingLabel: String {
        let segmentCount = project.effectiveClipSegments.count
        if segmentCount > 1 {
            return "\(segmentCount) segments / \(timestampLabel(for: previewDuration))"
        }

        return "\(timestampLabel(for: trimRange.start)) - \(timestampLabel(for: trimRange.end))"
    }

    private func timestampLabel(for timestamp: TimeInterval) -> String {
        let totalCentiseconds = Int((timestamp * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }

    private func loadSourceVideoDisplaySize(from url: URL?) async -> CGSize? {
        guard let url else { return nil }

        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            guard size.width > 0, size.height > 0 else { return nil }
            return size
        } catch {
            return nil
        }
    }
}

private struct ManualZoomFocusOverlay: View {
    let segment: ManualZoomSegment
    let onFocusChange: (NormalizedPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width, 1)
            let contentHeight = max(geometry.size.height, 1)
            let point = CGPoint(
                x: contentWidth * segment.focus.x,
                y: contentHeight * segment.focus.y
            )

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.90), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(
                        width: max(contentWidth / segment.zoomLevel, 52),
                        height: max(contentHeight / segment.zoomLevel, 52)
                    )
                    .position(point)
                    .allowsHitTesting(false)

                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(Color.orange)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.88), lineWidth: 2))
                        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
                }
                .contentShape(Circle())
                .position(point)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let focus = NormalizedPoint(
                                    x: (value.location.x / contentWidth).clamped(to: 0...1),
                                    y: (value.location.y / contentHeight).clamped(to: 0...1)
                                )
                                onFocusChange(focus)
                            }
                    )

                Text("Drag dot to set zoom area")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.42), in: Capsule())
                    .position(x: min(max(point.x, 96), geometry.size.width - 96), y: min(point.y + 34, geometry.size.height - 18))
                    .allowsHitTesting(false)
            }
        }
    }
}

struct RealtimePreviewGeometry {
    let sourceSize: CGSize
    let contentRect: CGRect
    let cropRect: CGRect
    let displayRect: CGRect
    let videoFrame: CGRect

    init(
        sourceSize: CGSize,
        contentRect: CGRect,
        snapshot: FrameSnapshot,
        preservesFullSourceAtBase: Bool = false,
        cropPlanner: SourceCropPlanner = SourceCropPlanner()
    ) {
        let safeSourceSize = CGSize(
            width: max(sourceSize.width, 1),
            height: max(sourceSize.height, 1)
        )
        let safeContentRect = CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: max(contentRect.width, 1),
            height: max(contentRect.height, 1)
        )
        let sourceExtent = CGRect(origin: .zero, size: safeSourceSize)
        let presentation = cropPlanner.presentation(
            for: sourceExtent,
            contentRect: safeContentRect,
            snapshot: snapshot,
            preservesFullSourceAtBase: preservesFullSourceAtBase
        )
        let cropRect = presentation.cropRect
        let displayRect = presentation.displayRect
        let scale = max(displayRect.width / max(cropRect.width, 1), displayRect.height / max(cropRect.height, 1))
        let frameSize = CGSize(
            width: safeSourceSize.width * scale,
            height: safeSourceSize.height * scale
        )
        let cropTop = safeSourceSize.height - cropRect.maxY
        let frameOrigin = CGPoint(
            x: displayRect.minX - (cropRect.minX * scale),
            y: displayRect.minY - (cropTop * scale)
        )

        self.sourceSize = safeSourceSize
        self.contentRect = safeContentRect
        self.cropRect = cropRect
        self.displayRect = displayRect
        self.videoFrame = CGRect(origin: frameOrigin, size: frameSize)
    }

    func contentPoint(for normalizedPoint: NormalizedPoint) -> CGPoint {
        SourceCropPlanner().mappedContentPoint(
            for: normalizedPoint,
            in: CGRect(origin: .zero, size: sourceSize),
            cropRect: cropRect,
            layout: RenderLayout(renderSize: contentRect.size, padding: 0),
            displayRect: displayRect
        )
    }
}

private struct PreviewVideoPlayerView: NSViewRepresentable {
    let url: URL
    let seekTime: TimeInterval
    let displayTime: TimeInterval
    let playbackTimeline: PreviewPlaybackTimeline
    var pointerSnapshot: PointerSnapshot?
    var frameSnapshot: FrameSnapshot?
    var realtimeGeometry: RealtimePreviewGeometry?
    var contentCornerRadius: CGFloat = 0
    var showsReconstructedCursor = false
    var presenterVideoURL: URL?
    var presenterSeekTime: TimeInterval = 0
    var presenterLayout: PresenterOverlayLayout?
    var presenterShadowOpacity: Double = 0
    let onDisplaySeekRequested: (TimeInterval) -> Void
    let onPlaybackTimeChange: (TimeInterval) -> Void
    let onPlaybackEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> StablePlayerContainerView {
        let container = StablePlayerContainerView()
        updateNSView(container, context: context)
        return container
    }

    func updateNSView(_ nsView: StablePlayerContainerView, context: Context) {
        context.coordinator.onPlaybackTimeChange = onPlaybackTimeChange
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.playbackTimeline = playbackTimeline
        nsView.updateRealtimeOverlay(
            snapshot: pointerSnapshot,
            frameSnapshot: frameSnapshot,
            geometry: realtimeGeometry,
            cornerRadius: contentCornerRadius,
            showsCursor: showsReconstructedCursor
        )
        context.coordinator.presenterRenderOffset = presenterSeekTime - seekTime
        nsView.updatePresenterOverlay(
            url: presenterVideoURL,
            seekTime: presenterSeekTime,
            layout: presenterLayout,
            shadowOpacity: presenterShadowOpacity,
            renderOffset: context.coordinator.presenterRenderOffset,
            shouldSeek: context.coordinator.shouldSeekPresenterDuringUpdate(
                mainSeekTime: seekTime,
                player: nsView.playerView.player
            )
        )
        nsView.updatePlaybackControls(
            timeline: playbackTimeline,
            displayTime: displayTime,
            onSeekRequested: onDisplaySeekRequested
        )

        if context.coordinator.url != url {
            let shouldResumePlayback = nsView.playerView.player.map { player in
                player.rate != 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            } ?? false
            context.coordinator.url = url
            context.coordinator.detachTimeObserver()
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .pause
            nsView.setPlayer(player)
            context.coordinator.attachTimeObserver(to: player, container: nsView)
            context.coordinator.attachEndObserver(to: player, container: nsView)
            seek(
                player: player,
                coordinator: context.coordinator,
                container: nsView,
                to: seekTime,
                force: true,
                resumePlayback: shouldResumePlayback
            )
            return
        }

        if let player = nsView.playerView.player {
            seek(
                player: player,
                coordinator: context.coordinator,
                container: nsView,
                to: seekTime,
                force: false,
                resumePlayback: false
            )
        }
    }

    static func dismantleNSView(_ nsView: StablePlayerContainerView, coordinator: Coordinator) {
        coordinator.detachTimeObserver()
        nsView.setPlayer(nil)
    }

    private func seek(
        player: AVPlayer,
        coordinator: Coordinator,
        container: StablePlayerContainerView,
        to timestamp: TimeInterval,
        force: Bool,
        resumePlayback: Bool
    ) {
        let safeTimestamp = max(timestamp, 0)
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let referenceTime = currentTime.isFinite ? currentTime : coordinator.seekTime

        if !force {
            if abs(coordinator.lastPlaybackReportTime - safeTimestamp) <= 0.12 {
                coordinator.seekTime = safeTimestamp
                return
            }

            if player.rate == 0 {
                if abs(coordinator.lastPlaybackReportTime - safeTimestamp) <= 0.08 {
                    coordinator.seekTime = safeTimestamp
                    return
                }
            } else {
                let reportDelta = abs(coordinator.lastPlaybackReportTime - safeTimestamp)
                let currentDelta = abs(referenceTime - safeTimestamp)
                guard reportDelta > 0.5, currentDelta > 0.5 else {
                    coordinator.seekTime = safeTimestamp
                    return
                }
            }
        }

        let threshold = player.rate == 0 ? 0.04 : 0.5
        guard force || abs(referenceTime - safeTimestamp) > threshold else { return }

        coordinator.seekTime = safeTimestamp
        let time = CMTime(seconds: safeTimestamp, preferredTimescale: 600)
        let tolerance = force ? .zero : CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        coordinator.isSeekingProgrammatically = true
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                coordinator.isSeekingProgrammatically = false
                if resumePlayback {
                    player.play()
                }
                container.syncPresenterPlaybackState()
            }
        }
    }

    final class Coordinator {
        var url: URL?
        var seekTime: TimeInterval = -1
        var lastPlaybackReportTime: TimeInterval = -1
        var isSeekingProgrammatically = false
        var timeObserver: Any?
        var endObserver: NSObjectProtocol?
        weak var observedPlayer: AVPlayer?
        var onPlaybackTimeChange: ((TimeInterval) -> Void)?
        var onPlaybackEnded: (() -> Void)?
        var playbackTimeline: PreviewPlaybackTimeline?
        var presenterRenderOffset: TimeInterval = 0

        func shouldSeekPresenterDuringUpdate(mainSeekTime: TimeInterval, player: AVPlayer?) -> Bool {
            guard let player else { return true }
            let safeSeekTime = max(mainSeekTime, 0)
            guard player.rate != 0 else { return true }
            guard lastPlaybackReportTime >= 0 else { return true }
            return abs(lastPlaybackReportTime - safeSeekTime) > 0.12
        }

        func attachTimeObserver(to player: AVPlayer, container: StablePlayerContainerView) {
            observedPlayer = player
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
                queue: .main
            ) { [weak self, weak container] time in
                guard let self, !self.isSeekingProgrammatically else { return }
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                self.seekTime = seconds
                self.lastPlaybackReportTime = seconds
                container?.updatePlaybackProgress(sourceTime: seconds)
                container?.updatePresenterProgress(sourceTime: seconds + self.presenterRenderOffset)
                self.onPlaybackTimeChange?(seconds)
            }
        }

        func detachTimeObserver() {
            if let timeObserver, let observedPlayer {
                observedPlayer.removeTimeObserver(timeObserver)
            }
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            timeObserver = nil
            endObserver = nil
            observedPlayer = nil
        }

        func attachEndObserver(to player: AVPlayer, container: StablePlayerContainerView) {
            guard let item = player.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self, weak player, weak container] _ in
                guard let self, let player else { return }
                player.pause()
                container?.syncPresenterPlaybackState()
                DispatchQueue.main.async { [weak self, weak container] in
                    guard let self else { return }
                    self.seekTime = 0
                    self.lastPlaybackReportTime = 0
                    container?.updatePlaybackProgress(displayTime: 0)
                    self.onPlaybackEnded?()
                }
            }
        }
    }
}

private final class StablePlayerContainerView: NSView {
    let playerView = StableAVPlayerView()
    private let videoClipView = FlippedVideoClipView()
    private let videoClipMaskLayer = CAShapeLayer()
    private let cursorOverlayView = CursorOverlayView()
    private let presenterOverlayView = PresenterBubblePlayerView()
    private let controlsView = PlaybackControlsView()
    private var realtimeGeometry: RealtimePreviewGeometry?
    private var contentCornerRadius: CGFloat = 0
    private var playbackTimeline: PreviewPlaybackTimeline?
    private var presenterLayout: PresenterOverlayLayout?
    private var presenterVideoURL: URL?
    private var presenterRenderOffset: TimeInterval = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        videoClipView.wantsLayer = true
        videoClipView.layer?.backgroundColor = NSColor.clear.cgColor
        videoClipView.layer?.masksToBounds = true
        videoClipView.layer?.mask = videoClipMaskLayer
        videoClipView.translatesAutoresizingMaskIntoConstraints = true

        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        playerView.translatesAutoresizingMaskIntoConstraints = true

        cursorOverlayView.translatesAutoresizingMaskIntoConstraints = true
        presenterOverlayView.translatesAutoresizingMaskIntoConstraints = true

        controlsView.translatesAutoresizingMaskIntoConstraints = true

        addSubview(videoClipView)
        videoClipView.addSubview(playerView)
        addSubview(cursorOverlayView)
        addSubview(presenterOverlayView)
        addSubview(controlsView)
        controlsView.onPlaybackCommand = { [weak self] in
            self?.syncPresenterPlaybackState()
        }

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        cursorOverlayView.frame = bounds
        let controlsHeight: CGFloat = 46
        controlsView.frame = CGRect(
            x: 12,
            y: max(bounds.height - controlsHeight - 12, 12),
            width: max(bounds.width - 24, 120),
            height: controlsHeight
        )
        applyVideoGeometry()
        if let geometry = realtimeGeometry {
            playerView.frame = geometry.videoFrame.offsetBy(
                dx: -geometry.displayRect.minX,
                dy: -geometry.displayRect.minY
            )
        } else {
            playerView.frame = videoClipView.bounds
        }
        applyPresenterGeometry()
        controlsView.layer?.zPosition = 100
        presenterOverlayView.layer?.zPosition = 75
        cursorOverlayView.layer?.zPosition = 50
    }

    func setPlayer(_ player: AVPlayer?) {
        playerView.player = player
        controlsView.player = player
        controlsView.updateState()
        syncPresenterPlaybackState()
    }

    func updatePlaybackControls(
        timeline: PreviewPlaybackTimeline,
        displayTime: TimeInterval,
        onSeekRequested: @escaping (TimeInterval) -> Void
    ) {
        playbackTimeline = timeline
        controlsView.updateTimeline(
            displayTime: displayTime,
            displayDuration: timeline.displayDuration,
            onSeekRequested: { [weak self] displayTime in
                if let self {
                    let presenterTime = timeline.sourceTime(forDisplayTime: displayTime) + self.presenterRenderOffset
                    self.seekPresenter(to: presenterTime)
                    self.syncPresenterPlaybackState()
                }
                onSeekRequested(displayTime)
            }
        )
        controlsView.updateState()
    }

    func updateRealtimeOverlay(
        snapshot: PointerSnapshot?,
        frameSnapshot: FrameSnapshot?,
        geometry: RealtimePreviewGeometry?,
        cornerRadius: CGFloat,
        showsCursor: Bool
    ) {
        realtimeGeometry = geometry
        contentCornerRadius = max(cornerRadius, 0)
        applyVideoGeometry()
        if let geometry {
            playerView.frame = geometry.videoFrame.offsetBy(
                dx: -geometry.displayRect.minX,
                dy: -geometry.displayRect.minY
            )
        } else {
            playerView.frame = videoClipView.bounds
        }
        cursorOverlayView.snapshot = snapshot
        cursorOverlayView.cameraFocus = frameSnapshot?.focus
        cursorOverlayView.geometry = geometry
        cursorOverlayView.showsCursor = showsCursor
        cursorOverlayView.showsDebugOverlay = ProcessInfo.processInfo.environment["MOUSELENS_DEBUG_COORDINATES"] == "1"
        cursorOverlayView.needsDisplay = true
        needsLayout = true
        controlsView.updateState()
    }

    func updatePresenterOverlay(
        url: URL?,
        seekTime: TimeInterval,
        layout: PresenterOverlayLayout?,
        shadowOpacity: Double,
        renderOffset: TimeInterval,
        shouldSeek: Bool
    ) {
        presenterLayout = layout
        presenterRenderOffset = renderOffset

        let didChangeURL = presenterVideoURL != url
        if didChangeURL {
            presenterVideoURL = url
            if let url {
                let player = AVPlayer(url: url)
                player.actionAtItemEnd = .pause
                presenterOverlayView.player = player
            } else {
                presenterOverlayView.player = nil
            }
        }

        presenterOverlayView.cornerRadius = layout?.clippingPathCornerRadius ?? 0
        presenterOverlayView.shadowOpacity = CGFloat(shadowOpacity.clamped(to: 0...1))
        applyPresenterGeometry()
        if didChangeURL || shouldSeek {
            seekPresenter(to: seekTime)
        }
        syncPresenterPlaybackState()
    }

    func updatePresenterProgress(sourceTime: TimeInterval) {
        correctPresenterDrift(toward: sourceTime)
        syncPresenterPlaybackState()
    }

    func updatePlaybackProgress(sourceTime: TimeInterval) {
        if let playbackTimeline {
            controlsView.updateDisplayTime(playbackTimeline.displayTime(forPlaybackTime: sourceTime))
        }
        controlsView.updateState()
    }

    func updatePlaybackProgress(displayTime: TimeInterval) {
        controlsView.updateDisplayTime(displayTime)
        controlsView.updateState()
    }

    func syncPresenterPlaybackState() {
        guard let presenterPlayer = presenterOverlayView.player else { return }
        guard let mainPlayer = playerView.player else {
            presenterPlayer.pause()
            return
        }

        let mainRate = mainPlayer.rate
        if mainRate == 0 {
            presenterPlayer.pause()
        } else if presenterPlayer.rate != mainRate {
            presenterPlayer.rate = mainRate
        }
    }

    private func applyVideoGeometry() {
        videoClipView.frame = realtimeGeometry?.displayRect ?? bounds
        videoClipView.layer?.cornerRadius = contentCornerRadius
        videoClipView.layer?.masksToBounds = true
        updateVideoMask()
    }

    private func updateVideoMask() {
        let clipBounds = videoClipView.bounds
        videoClipMaskLayer.frame = clipBounds
        videoClipMaskLayer.path = CGPath(
            roundedRect: clipBounds,
            cornerWidth: contentCornerRadius,
            cornerHeight: contentCornerRadius,
            transform: nil
        )
    }

    private func applyPresenterGeometry() {
        guard let layout = presenterLayout, presenterVideoURL != nil else {
            presenterOverlayView.frame = .zero
            presenterOverlayView.isHidden = true
            return
        }

        presenterOverlayView.isHidden = false
        presenterOverlayView.frame = layout.frame
    }

    private func seekPresenter(to timestamp: TimeInterval) {
        guard let player = presenterOverlayView.player else { return }
        let safeTimestamp = max(timestamp, 0)
        let currentTime = CMTimeGetSeconds(player.currentTime())
        guard !currentTime.isFinite || abs(currentTime - safeTimestamp) > 0.08 else { return }

        player.seek(
            to: CMTime(seconds: safeTimestamp, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        )
    }

    private func correctPresenterDrift(toward timestamp: TimeInterval) {
        guard let player = presenterOverlayView.player else { return }
        let safeTimestamp = max(timestamp, 0)
        let currentTime = CMTimeGetSeconds(player.currentTime())
        guard !currentTime.isFinite || abs(currentTime - safeTimestamp) > 0.75 else { return }
        seekPresenter(to: safeTimestamp)
    }
}

private final class FlippedVideoClipView: NSView {
    override var isFlipped: Bool { true }
}

private final class StableAVPlayerView: AVPlayerView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private final class PresenterBubblePlayerView: AVPlayerView {
    private let maskLayer = CAShapeLayer()
    var cornerRadius: CGFloat = 0 {
        didSet { updateMask() }
    }
    var shadowOpacity: CGFloat = 0 {
        didSet { updateShadow() }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controlsStyle = .none
        videoGravity = .resizeAspectFill
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = false
        layer?.mask = maskLayer
        translatesAutoresizingMaskIntoConstraints = true
        updateShadow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        maskLayer.frame = bounds
        maskLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    private func updateShadow() {
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(shadowOpacity)
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: 5)
    }
}

private final class PlaybackControlsView: NSView {
    weak var player: AVPlayer?
    var onPlaybackCommand: (() -> Void)?

    private let playPauseButton = NSButton()
    private let currentTimeLabel = NSTextField(labelWithString: "00:00.00")
    private let durationLabel = NSTextField(labelWithString: "00:00.00")
    private let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var isScrubbing = false
    private var displayTime: TimeInterval = 0
    private var displayDuration: TimeInterval = 0
    private var onSeekRequested: ((TimeInterval) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.46).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        playPauseButton.bezelStyle = .texturedRounded
        playPauseButton.isBordered = true
        playPauseButton.title = "▶"
        playPauseButton.font = .systemFont(ofSize: 13, weight: .semibold)
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayback)

        for label in [currentTimeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.88)
            label.alignment = .center
        }

        progressSlider.target = self
        progressSlider.action = #selector(scrub)
        progressSlider.isContinuous = true

        addSubview(playPauseButton)
        addSubview(currentTimeLabel)
        addSubview(progressSlider)
        addSubview(durationLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let buttonWidth: CGFloat = 34
        let labelWidth: CGFloat = 62
        let centerY = (bounds.height - 26) / 2

        playPauseButton.frame = CGRect(x: inset, y: centerY, width: buttonWidth, height: 26)
        currentTimeLabel.frame = CGRect(x: playPauseButton.frame.maxX + 8, y: centerY + 3, width: labelWidth, height: 20)
        durationLabel.frame = CGRect(x: bounds.width - inset - labelWidth, y: centerY + 3, width: labelWidth, height: 20)
        progressSlider.frame = CGRect(
            x: currentTimeLabel.frame.maxX + 8,
            y: centerY + 2,
            width: max(durationLabel.frame.minX - currentTimeLabel.frame.maxX - 16, 24),
            height: 22
        )
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }

    func updateTimeline(
        displayTime: TimeInterval,
        displayDuration: TimeInterval,
        onSeekRequested: @escaping (TimeInterval) -> Void
    ) {
        self.displayTime = max(displayTime, 0)
        self.displayDuration = max(displayDuration, 0)
        self.onSeekRequested = onSeekRequested
    }

    func updateDisplayTime(_ displayTime: TimeInterval) {
        self.displayTime = max(displayTime, 0)
    }

    func updateState() {
        let duration = max(displayDuration, 0)
        let currentTime = displayTime.clamped(to: 0...max(duration, 0))
        let isPlaying = (player?.rate ?? 0) != 0
        playPauseButton.title = isPlaying ? "Ⅱ" : "▶"
        currentTimeLabel.stringValue = formatTimestamp(currentTime)
        durationLabel.stringValue = formatTimestamp(duration)

        if !isScrubbing {
            progressSlider.doubleValue = duration > 0 ? (currentTime / duration).clamped(to: 0...1) : 0
        }
    }

    @objc private func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
        onPlaybackCommand?()
        updateState()
    }

    @objc private func scrub() {
        let duration = max(displayDuration, 0)
        guard duration > 0 else { return }

        isScrubbing = true
        let seconds = progressSlider.doubleValue.clamped(to: 0...1) * duration
        currentTimeLabel.stringValue = formatTimestamp(seconds)
        onSeekRequested?(seconds)
        DispatchQueue.main.async { [weak self] in
            self?.isScrubbing = false
            self?.updateState()
        }
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let totalCentiseconds = Int((max(timestamp, 0) * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

private final class CursorOverlayView: NSView {
    var snapshot: PointerSnapshot?
    var cameraFocus: NormalizedPoint?
    var geometry: RealtimePreviewGeometry?
    var showsCursor = false
    var showsDebugOverlay = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let snapshot, let geometry else { return }

        if snapshot.isClickActive, let clickLocation = snapshot.clickLocation {
            let point = overlayPoint(for: clickLocation, geometry: geometry)
            drawClickRipple(at: point, progress: snapshot.clickProgress)
        }

        if showsCursor {
            drawCursor(at: overlayPoint(for: snapshot.location, geometry: geometry))
        }

        if showsDebugOverlay {
            drawDebugCalibration(snapshot: snapshot, cameraFocus: cameraFocus, geometry: geometry)
        }
    }

    private func overlayPoint(for normalizedPoint: NormalizedPoint, geometry: RealtimePreviewGeometry) -> CGPoint {
        geometry.contentPoint(for: normalizedPoint)
    }

    private func drawClickRipple(at point: CGPoint, progress: Double) {
        let easedProgress = CGFloat(progress.clamped(to: 0...1))
        let diameter = 30 + (36 * (1 - easedProgress))
        let rect = CGRect(
            x: point.x - (diameter / 2),
            y: point.y - (diameter / 2),
            width: diameter,
            height: diameter
        )

        NSColor.white.withAlphaComponent(0.36 + (0.34 * easedProgress)).setStroke()
        let ring = NSBezierPath(ovalIn: rect)
        ring.lineWidth = 3
        ring.stroke()

        NSColor.white.withAlphaComponent(0.18 * easedProgress).setFill()
        NSBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)).fill()
    }

    private func drawCursor(at point: CGPoint) {
        let origin = CursorGeometry.origin(forTip: point, scale: 1)
        let transform = AffineTransform(translationByX: origin.x, byY: origin.y)
        let path = NSBezierPath()
        path.move(to: CursorGeometry.hotspot)
        path.line(to: CGPoint(x: 5, y: 35))
        path.line(to: CGPoint(x: 13, y: 27))
        path.line(to: CGPoint(x: 18, y: 40))
        path.line(to: CGPoint(x: 24, y: 37))
        path.line(to: CGPoint(x: 19, y: 25))
        path.line(to: CGPoint(x: 31, y: 25))
        path.close()
        path.transform(using: transform)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1.6
        path.stroke()
    }

    private func drawDebugCalibration(snapshot: PointerSnapshot, cameraFocus: NormalizedPoint?, geometry: RealtimePreviewGeometry) {
        drawDebugCross(
            at: overlayPoint(for: snapshot.rawLocation, geometry: geometry),
            color: NSColor.systemYellow,
            label: "raw"
        )

        if let clickLocation = snapshot.clickLocation {
            drawDebugCross(
                at: overlayPoint(for: clickLocation, geometry: geometry),
                color: NSColor.systemRed,
                label: "click"
            )
        }

        if let cameraFocus {
            drawDebugCross(
                at: overlayPoint(for: cameraFocus, geometry: geometry),
                color: NSColor.systemPurple,
                label: "focus"
            )
        }
    }

    private func drawDebugCross(at point: CGPoint, color: NSColor, label: String) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: point.x - 7, y: point.y))
        path.line(to: CGPoint(x: point.x + 7, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 7))
        path.line(to: CGPoint(x: point.x, y: point.y + 7))
        path.lineWidth = 2
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: color
        ]
        NSString(string: label).draw(
            at: CGPoint(x: point.x + 9, y: point.y - 7),
            withAttributes: attributes
        )
    }
}

private extension ProjectAspectRatio {
    var canvasAspectRatio: CGFloat {
        switch self {
        case .landscape:
            16.0 / 9.0
        case .portrait:
            9.0 / 16.0
        case .square:
            1.0
        }
    }
}
