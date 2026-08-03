import SwiftUI

struct ExportPanelView: View {
    @ObservedObject var viewModel: EditorViewModel
    let fixedWidth: CGFloat?
    let onBack: () -> Void

    private var isExporting: Bool {
        viewModel.exportState == .exporting
    }

    private var isGIF: Bool {
        viewModel.exportConfiguration.format == .gif
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Format")
                    formatCard(
                        title: "MP4",
                        subtitle: "4K / 30 fps default",
                        iconText: "H.264",
                        isSelected: viewModel.exportConfiguration.format == .mp4,
                        isEnabled: true,
                        action: { viewModel.updateExportFormat(.mp4) }
                    )
                    formatCard(
                        title: "GIF",
                        subtitle: "1080p / 15 fps default",
                        iconText: "GIF",
                        isSelected: viewModel.exportConfiguration.format == .gif,
                        isEnabled: true,
                        action: { viewModel.updateExportFormat(.gif) }
                    )

                    settingsHeader
                    settings

                    HStack {
                        Spacer()
                        Button("Reset to Recommended") {
                            viewModel.resetExportConfiguration()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .disabled(!viewModel.isExportConfigurationModified)
                    }
                    .frame(height: 28)

                    Text("Uses the current trim range, background, padding, corner radius, cursor, click feedback, and Zoom Track.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.mutedText.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    if case .failed(let message) = viewModel.exportState {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }

            footer
        }
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : fixedWidth)
        .background(Color.white.opacity(0.04))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)
            .help("Back to editor settings")

            Text("Export")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isExporting ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(isExporting ? "Exporting" : "Ready")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.mutedText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
    }

    private var settingsHeader: some View {
        HStack {
            sectionLabel("Settings")
            Spacer()
            Text(viewModel.isExportConfigurationModified ? "Modified" : "Recommended")
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(viewModel.isExportConfigurationModified ? Color.orange : Color.blue.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill((viewModel.isExportConfigurationModified ? Color.orange : Color.blue).opacity(0.12))
                        .strokeBorder((viewModel.isExportConfigurationModified ? Color.orange : Color.blue).opacity(0.28))
                )
        }
        .padding(.top, 6)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            settingsRow("Resolution") {
                Picker("Resolution", selection: Binding(
                    get: { viewModel.exportConfiguration.resolution },
                    set: { viewModel.updateExportResolution($0) }
                )) {
                    ForEach(
                        ExportConfiguration.allowedResolutions(for: viewModel.exportConfiguration.format),
                        id: \.self
                    ) { resolution in
                        Text(LocalizedStringKey(resolution.label)).tag(resolution)
                    }
                }
                .labelsHidden()
                .frame(width: 112)
            }

            Divider().overlay(Color.white.opacity(0.08))

            settingsRow("Frame Rate") {
                if isGIF {
                    Text("15 fps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    Picker("Frame Rate", selection: Binding(
                        get: { viewModel.exportConfiguration.frameRate },
                        set: { viewModel.updateExportFrameRate($0) }
                    )) {
                        ForEach(
                        ExportConfiguration.allowedFrameRates(for: viewModel.exportConfiguration.format),
                        id: \.self
                    ) { frameRate in
                            Text(LocalizedStringKey(frameRate.label)).tag(frameRate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                }
            }

            if !isGIF {
                Divider().overlay(Color.white.opacity(0.08))

                settingsRow("Quality") {
                    Picker("Quality", selection: Binding(
                        get: { viewModel.exportConfiguration.quality },
                        set: { viewModel.updateExportQuality($0) }
                    )) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(LocalizedStringKey(quality.label)).tag(quality)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                }

                Divider().overlay(Color.white.opacity(0.08))

                settingsRow("Include Cursor") {
                    Toggle("Include Cursor", isOn: Binding(
                        get: { viewModel.exportConfiguration.includesCursor },
                        set: { viewModel.updateExportIncludesCursor($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Divider().overlay(Color.white.opacity(0.08))

                settingsRow("Click Feedback") {
                    Toggle("Click Feedback", isOn: Binding(
                        get: { viewModel.exportConfiguration.includesClickFeedback },
                        set: { viewModel.updateExportIncludesClickFeedback($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.panelBorder.opacity(0.65))
        )
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if viewModel.showsGIFDurationWarning {
                Label(viewModel.gifDurationWarningText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let unavailableMessage = viewModel.exportUnavailableMessage {
                Label(unavailableMessage, systemImage: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedText.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("\(Text(LocalizedStringKey(viewModel.estimatedExportSizeCaption))): \(viewModel.estimatedExportSizeLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.mutedText.opacity(0.82))

            Button {
                Task { await viewModel.export() }
            } label: {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(LocalizedStringKey(isExporting ? "Exporting" : viewModel.exportButtonLabel))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExporting || !viewModel.canExportSelectedFormat)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 18)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .top) {
            Divider().overlay(AppTheme.panelBorder.opacity(0.5))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.mutedText.opacity(0.75))
    }

    private func formatCard(
        title: String,
        subtitle: String,
        iconText: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(iconText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 14, weight: .semibold))
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.mutedText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.white : AppTheme.mutedText, isSelected ? AppTheme.accent : Color.clear)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.accent.opacity(0.13) : Color.white.opacity(0.035))
                    .strokeBorder(isSelected ? AppTheme.accent : AppTheme.panelBorder.opacity(0.65))
            )
            .opacity(isEnabled ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.84))
            Spacer()
            content()
        }
        .frame(minHeight: 46)
    }
}
