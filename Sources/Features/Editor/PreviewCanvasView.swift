import AppKit
import SwiftUI

struct PreviewCanvasView: View {
    let project: RecordingProject
    let previewImage: NSImage?
    let isPreviewLoading: Bool
    let previewDuration: TimeInterval
    @Binding var previewTimestamp: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            previewStage

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(previewTitle, systemImage: previewImage == nil ? "scope" : "video")
                    Spacer()
                    Text(timestampLabel(for: previewTimestamp))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

                Slider(
                    value: $previewTimestamp,
                    in: 0...max(previewDuration, 0.01)
                )
                .disabled(previewDuration <= 0.01)

                Text(scrubberCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var previewStage: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppTheme.panelBorder.opacity(0.06))

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                } else {
                    fallbackPreview(in: geometry.size)
                }

                if isPreviewLoading {
                    ProgressView()
                        .controlSize(.large)
                        .padding(18)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fallbackPreview(in size: CGSize) -> some View {
        ZStack {
            project.style.background.gradient

            RoundedRectangle(cornerRadius: project.style.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.12), radius: project.style.shadowRadius, y: 16)
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
        previewImage == nil ? "Motion Preview" : "Frame Preview"
    }

    private var scrubberCaption: String {
        if previewImage == nil {
            return "Real frame preview appears after a recording source is available."
        }
        return "\(project.cameraKeyframes.count) keyframes mapped over the recorded source."
    }

    private func timestampLabel(for timestamp: TimeInterval) -> String {
        let totalCentiseconds = Int((timestamp * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
