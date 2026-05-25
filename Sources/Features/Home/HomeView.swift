import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onProjectReady: (RecordingProject) -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                recordingToolbar(isCompact: geometry.size.width < 1240)

                Divider()
                    .overlay(AppTheme.panelBorder.opacity(0.45))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $viewModel.showingPermissions) {
            PermissionGateView(
                viewModel: PermissionsViewModel(permissionManager: viewModel.permissionManager),
                requiresMicrophone: viewModel.includeMicrophone
            ) {
                Task { await viewModel.requestPermissions() }
            } onGranted: {
                viewModel.refreshPermissions()
                viewModel.showingPermissions = false
            }
            .frame(width: 520, height: 420)
        }
        .onAppear {
            viewModel.refreshPermissions()
        }
    }

    private func recordingToolbar(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                recordingToolbarContent(isCompact: true)
            } else {
                ViewThatFits(in: .horizontal) {
                    recordingToolbarContent(isCompact: false)
                    recordingToolbarContent(isCompact: true)
                }
            }
        }
        .padding(.leading, 34)
        .padding(.trailing, 24)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .background(Color.white.opacity(0.035))
    }

    private func recordingToolbarContent(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 10 : 14) {
            toolbarIdentity(isCompact: isCompact)
                .frame(width: isCompact ? 176 : 190, alignment: .leading)

            captureTargetControl(isCompact: isCompact)

            if viewModel.selectedCaptureTarget == .window {
                windowTargetControl(isCompact: isCompact)
            }

            ToolbarToggleButton(
                title: "Microphone",
                systemImage: viewModel.includeMicrophone ? "mic.fill" : "mic.slash.fill",
                isOn: viewModel.includeMicrophone
            ) {
                viewModel.includeMicrophone.toggle()
            }
            .disabled(viewModel.recordingState != .idle)

            ToolbarToggleButton(
                title: "System Audio",
                systemImage: viewModel.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                isOn: viewModel.includeSystemAudio
            ) {
                viewModel.includeSystemAudio.toggle()
            }
            .disabled(viewModel.recordingState != .idle)

            aspectRatioControl(isCompact: isCompact)

            Spacer(minLength: isCompact ? 8 : 14)

            Button {
                viewModel.refreshPermissions()
            } label: {
                Image(systemName: permissionIconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(permissionIconColor)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Refresh permissions")
            .disabled(viewModel.recordingState != .idle)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                Task { await handleRecordingToolbarAction() }
            } label: {
                Label(toolbarActionTitle, systemImage: toolbarActionIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: isCompact ? 94 : 116)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.permissions.needsScreenRecordingRelaunch)
        }
        .frame(maxWidth: .infinity)
    }

    private func toolbarIdentity(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MouseLens")
                .font(.system(size: isCompact ? 18 : 20, weight: .bold, design: .rounded))
                .lineLimit(1)

            if !isCompact {
                Text(toolbarSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(toolbarSubtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func captureTargetControl(isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            if !isCompact {
                Text("Capture Target")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 112, alignment: .leading)
                    .layoutPriority(3)
            }

            Picker("Capture Target", selection: $viewModel.selectedCaptureTarget) {
                ForEach(CaptureTarget.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: isCompact ? 170 : 214)
            .disabled(viewModel.recordingState != .idle)
        }
    }

    private func windowTargetControl(isCompact: Bool) -> some View {
        Menu {
            Button {
                Task { await viewModel.refreshWindowTargets() }
            } label: {
                Label("Refresh Windows", systemImage: "arrow.clockwise")
            }

            Divider()

            if viewModel.availableWindowTargets.isEmpty {
                Button("No recordable windows") {}
                    .disabled(true)
            } else {
                ForEach(viewModel.availableWindowTargets) { target in
                    Button {
                        viewModel.selectWindowTarget(target)
                    } label: {
                        Label(
                            target.displayLabel,
                            systemImage: target.id == viewModel.selectedWindowTargetID ? "checkmark" : "macwindow"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "macwindow")
                    .font(.system(size: 15, weight: .semibold))

                Text(viewModel.selectedWindowTargetLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if viewModel.isRefreshingWindowTargets {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .frame(width: isCompact ? 152 : 188, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(viewModel.recordingState != .idle)
        .help("Choose window to record")
    }

    private func aspectRatioControl(isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            if !isCompact {
                Text("Aspect Ratio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 98, alignment: .leading)
                    .layoutPriority(3)
            }

            Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                ForEach(ProjectAspectRatio.allCases, id: \.self) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            .labelsHidden()
            .frame(width: isCompact ? 72 : 78)
            .disabled(viewModel.recordingState != .idle)
        }
    }

    private var toolbarSubtitle: String {
        if !viewModel.isCanonicalLocalTestApp {
            return "Not running canonical local test app."
        }

        return viewModel.statusMessage
    }

    private var toolbarSubtitleColor: Color {
        viewModel.isCanonicalLocalTestApp ? AppTheme.mutedText : .orange
    }

    private var toolbarActionTitle: String {
        switch viewModel.recordingState {
        case .idle:
            return viewModel.permissions.needsScreenRecordingRelaunch ? "Reopen" : "Record"
        case .countdown:
            return "Cancel"
        case .recording:
            return "Stop"
        }
    }

    private var toolbarActionIcon: String {
        switch viewModel.recordingState {
        case .idle:
            return viewModel.permissions.needsScreenRecordingRelaunch ? "arrow.clockwise.circle.fill" : "record.circle.fill"
        case .countdown:
            return "xmark.circle.fill"
        case .recording:
            return "stop.circle.fill"
        }
    }

    private var permissionIconName: String {
        if viewModel.permissions.needsScreenRecordingRelaunch {
            return "arrow.clockwise.shield"
        }

        return viewModel.permissions.recordingReady(requiresMicrophone: viewModel.includeMicrophone)
            ? "checkmark.shield"
            : "exclamationmark.shield"
    }

    private var permissionIconColor: Color {
        viewModel.permissions.recordingReady(requiresMicrophone: viewModel.includeMicrophone)
            ? AppTheme.mutedText
            : .orange
    }

    private func handleRecordingToolbarAction() async {
        switch viewModel.recordingState {
        case .idle:
            await viewModel.startRecording()
        case .countdown:
            viewModel.cancelCountdown()
        case .recording:
            await viewModel.stopRecording()
        }
    }
}

private struct ToolbarToggleButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 40)
                .foregroundStyle(isOn ? .white : AppTheme.mutedText)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? AppTheme.accent.opacity(0.95) : Color.white.opacity(0.075))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(isOn ? 0.26 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
