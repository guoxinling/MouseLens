import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    let project: RecordingProject
    let onBack: () -> Void

    var body: some View {
        let displayProject = viewModel.project ?? project

        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(displayProject.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Fine-tune the motion plan and export a polished MP4 from the recorded source.")
                    .foregroundStyle(AppTheme.mutedText)

                controls

                Spacer()

                Button {
                    Task { await viewModel.export() }
                } label: {
                    Label(viewModel.exportState == .exporting ? "Exporting…" : "Export MP4", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.exportState == .exporting)

                if case .failed(let message) = viewModel.exportState {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 320, alignment: .topLeading)
            .padding(28)
            .cardStyle()

            VStack(alignment: .leading, spacing: 20) {
                PreviewCanvasView(
                    project: displayProject,
                    previewImage: viewModel.previewImage,
                    isPreviewLoading: viewModel.isPreviewLoading,
                    previewDuration: viewModel.previewDuration,
                    previewTimestamp: Binding(
                        get: { viewModel.previewTimestamp },
                        set: { viewModel.updatePreviewTimestamp($0) }
                    )
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                timeline(project: displayProject, currentTimestamp: viewModel.previewTimestamp)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(32)
        .task(id: project.id) {
            viewModel.configure(for: project)
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            ExportSheetView(exportURL: viewModel.exportURL)
                .frame(width: 520, height: 240)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Controls")
                .font(.headline)

            MetricSlider(label: "Follow Strength", value: $viewModel.followStrength, range: 0.2...1.0)
            MetricSlider(label: "Click Emphasis", value: $viewModel.clickEmphasis, range: 0.0...0.8)
            MetricSlider(label: "Padding", value: $viewModel.padding, range: 0.02...0.2)
            MetricSlider(label: "Corner Radius", value: $viewModel.cornerRadius, range: 12...42)

            Picker("Background", selection: $viewModel.selectedBackground) {
                ForEach(ProjectBackgroundStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }

            Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                ForEach(ProjectAspectRatio.allCases, id: \.self) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }

            Picker("Preset", selection: $viewModel.exportPreset) {
                ForEach(ExportPreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
        }
    }

    private func timeline(project: RecordingProject, currentTimestamp: TimeInterval) -> some View {
        let maxTimestamp = max(project.duration, project.cameraKeyframes.last?.timestamp ?? 0.01)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Motion Timeline")
                    .font(.headline)
                Spacer()
                Text(timestampLabel(for: currentTimestamp))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.mutedText)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.panelBorder.opacity(0.08))

                    Path { path in
                        let frames = project.cameraKeyframes
                        guard let first = frames.first, let last = frames.last, last.timestamp > first.timestamp else { return }

                        for (index, frame) in frames.enumerated() {
                            let x = geometry.size.width * CGFloat(frame.timestamp / last.timestamp)
                            let y = geometry.size.height * CGFloat(1 - ((frame.zoom - 1.0) / 0.8).clamped(to: 0...1))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)

                    let markerX = geometry.size.width * CGFloat((currentTimestamp / maxTimestamp).clamped(to: 0...1))
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.8))
                        .frame(width: 2)
                        .padding(.vertical, 12)
                        .offset(x: markerX)
                }
            }
            .frame(height: 120)
        }
        .padding(24)
        .cardStyle()
    }

    private func timestampLabel(for timestamp: TimeInterval) -> String {
        let totalCentiseconds = Int((timestamp * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
