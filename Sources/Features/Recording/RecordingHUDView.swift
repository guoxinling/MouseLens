import AVFoundation
import SwiftUI

struct RecordingHUDView: View {
    let state: RecordingState
    let shortcutHint: String
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(titleText, systemImage: iconName)
                    .foregroundStyle(iconColor)
                Spacer()
                statusClock
            }

            Text(descriptionText)
                .foregroundStyle(AppTheme.mutedText)

            Text("Global shortcut: \(shortcutHint)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.accent)

            Button(role: buttonRole, action: onPrimaryAction) {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(buttonTint)
            .controlSize(.large)
        }
        .padding(28)
        .cardStyle()
    }

    @ViewBuilder
    private var statusClock: some View {
        switch state {
        case .idle:
            Text("00:00")
                .font(.system(.body, design: .monospaced))
        case .countdown(let secondsRemaining):
            Text(String(format: "00:%02d", secondsRemaining))
                .font(.system(.body, design: .monospaced))
        case .recording(let session):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsedText(for: session, now: context.date))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var titleText: String {
        switch state {
        case .idle:
            return "Ready"
        case .countdown(let secondsRemaining):
            return "Starting in \(secondsRemaining)"
        case .recording(let session):
            return session.isPaused ? "Paused" : "Recording"
        }
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "circle.dashed"
        case .countdown:
            return "timer"
        case .recording(let session):
            return session.isPaused ? "pause.circle.fill" : "record.circle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:
            return AppTheme.mutedText
        case .countdown:
            return .orange
        case .recording(let session):
            return session.isPaused ? .orange : .red
        }
    }

    private var descriptionText: String {
        switch state {
        case .idle:
            return "MouseLens is ready for the next walkthrough."
        case .countdown:
            return "MouseLens will hide its window before capture begins so the control panel does not end up in the recording."
        case .recording:
            return "Pointer activity is being tracked for automatic zoom and smooth camera motion even while the app window stays hidden."
        }
    }

    private var primaryButtonTitle: String {
        switch state {
        case .idle:
            return "Start Recording"
        case .countdown:
            return "Cancel Countdown"
        case .recording:
            return "Stop Recording"
        }
    }

    private var primaryButtonIcon: String {
        switch state {
        case .idle:
            return "play.circle.fill"
        case .countdown:
            return "xmark.circle.fill"
        case .recording:
            return "stop.circle.fill"
        }
    }

    private var buttonTint: Color {
        switch state {
        case .idle:
            return AppTheme.accent
        case .countdown:
            return .orange
        case .recording:
            return .red
        }
    }

    private var buttonRole: ButtonRole? {
        switch state {
        case .recording:
            return .destructive
        case .idle, .countdown:
            return nil
        }
    }

    private func elapsedText(for session: RecordingSessionState, now: Date) -> String {
        let duration = max(0, Int(session.elapsed(at: now)))
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct FloatingRecordingToolbarView: View {
    let session: RecordingSessionState
    let presenterPreviewSession: AVCaptureSession?
    let onPauseResume: () -> Void
    let onStop: () -> Void

    static func contentSize(hasPresenterPreview: Bool) -> CGSize {
        hasPresenterPreview ? CGSize(width: 472, height: 96) : CGSize(width: 360, height: 58)
    }

    var body: some View {
        HStack(spacing: 14) {
            if let presenterPreviewSession {
                PresenterLivePreviewBubble(session: presenterPreviewSession)
                    .frame(width: 72, height: 72)
                    .padding(.leading, 12)
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.isPaused ? .orange : .red)
                        .frame(width: 9, height: 9)

                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Text(elapsedText(now: context.date))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 56, alignment: .leading)
                    }
                }
                .padding(.leading, presenterPreviewSession == nil ? 14 : 0)

                Divider()
                    .frame(height: 24)
                    .overlay(Color.white.opacity(0.22))

                Button(action: onPauseResume) {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(.plain)
                .help(session.isPaused ? "Resume recording" : "Pause recording")

                Button(role: .destructive, action: onStop) {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.88))
                        )
                }
                .buttonStyle(.plain)
                .help("Finish recording")

                Spacer(minLength: 0)
            }
        }
        .frame(
            width: Self.contentSize(hasPresenterPreview: presenterPreviewSession != nil).width,
            height: Self.contentSize(hasPresenterPreview: presenterPreviewSession != nil).height
        )
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func elapsedText(now: Date) -> String {
        let duration = max(0, Int(session.elapsed(at: now)))
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct PresenterLivePreviewBubble: View {
    let session: AVCaptureSession

    var body: some View {
        PresenterCameraPreviewView(session: session)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
            .accessibilityLabel("Presenter camera preview")
    }
}

struct PresenterPreflightBubbleView: View {
    let session: AVCaptureSession
    let style: PresenterBubbleStyle

    var body: some View {
        GeometryReader { geometry in
            PresenterCameraPreviewView(session: session)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: geometry.size.width * CGFloat(style.cornerRadiusRatio),
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: geometry.size.width * CGFloat(style.cornerRadiusRatio),
                        style: .continuous
                    )
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(style.shadowOpacity),
                    radius: max(10, geometry.size.width * 0.08),
                    x: 0,
                    y: max(6, geometry.size.width * 0.04)
                )
        }
        .accessibilityLabel("Presenter camera bubble")
    }
}

struct PresenterCameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PresenterCameraPreviewNSView {
        let view = PresenterCameraPreviewNSView()
        view.update(session: session)
        return view
    }

    func updateNSView(_ nsView: PresenterCameraPreviewNSView, context: Context) {
        nsView.update(session: session)
    }
}

final class PresenterCameraPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroring()
    }

    func update(session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        applyMirroring()
    }

    private func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}

struct FloatingCountdownToolbarView: View {
    let secondsRemaining: Int
    let shortcutHint: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Starting in")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("\(secondsRemaining)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)

            Text(shortcutHint)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.mutedText)

            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.88))
                    )
            }
            .buttonStyle(.plain)
            .help("Cancel countdown")
            .padding(.trailing, 12)
        }
        .frame(width: 360, height: 58)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
