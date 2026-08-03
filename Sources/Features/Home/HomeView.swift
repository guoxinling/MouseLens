import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onProjectReady: (RecordingProject) -> Void
    @State private var showingNotesPopover = false

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
                requiresMicrophone: viewModel.includeMicrophone,
                requiresPresenterCamera: viewModel.includePresenterCamera
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
            viewModel.captureToolbarDidAppear()
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
                .layoutPriority(0)

            captureTargetControl(isCompact: isCompact)
                .layoutPriority(2)

            if viewModel.selectedCaptureTarget == .window {
                windowTargetControl(isCompact: isCompact)
                    .layoutPriority(0)
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

            ToolbarToggleButton(
                title: "Presenter",
                systemImage: viewModel.includePresenterCamera ? "video.fill" : "video.slash.fill",
                isOn: viewModel.includePresenterCamera
            ) {
                viewModel.includePresenterCamera.toggle()
            }
            .disabled(viewModel.recordingState != .idle)

            notesControl
                .disabled(viewModel.recordingState != .idle)

            aspectRatioControl(isCompact: isCompact)
                .layoutPriority(2)

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
                Label(LocalizedStringKey(toolbarActionTitle), systemImage: toolbarActionIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: isCompact ? 94 : 116)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isRecordingActionDisabled)
            .layoutPriority(10)
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

            Picker(
                "Capture Target",
                selection: Binding(
                    get: { viewModel.selectedCaptureTarget },
                    set: { viewModel.selectCaptureTarget($0) }
                )
            ) {
                ForEach(CaptureTarget.allCases, id: \.self) { option in
                    Text(LocalizedStringKey(option.label)).tag(option)
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
            .frame(
                minWidth: isCompact ? 104 : 126,
                idealWidth: isCompact ? 136 : 164,
                maxWidth: isCompact ? 150 : 178,
                minHeight: 40,
                idealHeight: 40,
                maxHeight: 40
            )
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

    private var notesControl: some View {
        Button {
            showingNotesPopover.toggle()
        } label: {
            Image(systemName: viewModel.recordingNotes.hasContent ? "note.text" : "note.text.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 40)
                .foregroundStyle(viewModel.recordingNotes.hasContent ? .white : AppTheme.mutedText)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(viewModel.recordingNotes.hasContent ? AppTheme.accent.opacity(0.95) : Color.white.opacity(0.075))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(viewModel.recordingNotes.hasContent ? 0.26 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Recording notes")
        .popover(isPresented: $showingNotesPopover, arrowEdge: .bottom) {
            RecordingNotesPopover(viewModel: viewModel)
                .frame(width: 360)
                .padding(16)
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

        return viewModel.permissions.recordingReady(
            requiresMicrophone: viewModel.includeMicrophone,
            requiresPresenterCamera: viewModel.includePresenterCamera
        )
            ? "checkmark.shield"
            : "exclamationmark.shield"
    }

    private var permissionIconColor: Color {
        viewModel.permissions.recordingReady(
            requiresMicrophone: viewModel.includeMicrophone,
            requiresPresenterCamera: viewModel.includePresenterCamera
        )
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

private struct RecordingNotesPopover: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("Recording Notes")
                    .font(.system(size: 16, weight: .bold))
            }

            TextEditor(text: notesTextBinding)
                .font(.system(size: 13, weight: .medium))
                .scrollContentBackground(.hidden)
                .frame(height: 132)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            Toggle("Show while recording", isOn: notesVisibleBinding)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text Size")
                    Spacer()
                    Text(String(format: "%.2f", viewModel.recordingNotes.fontScale))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .font(.system(size: 12, weight: .semibold))

                Slider(value: notesFontScaleBinding, in: 0.8...1.6)
            }

            HStack {
                Spacer()
                Button("Clear") {
                    viewModel.recordingNotes = .defaultValue
                }
                .disabled(viewModel.recordingNotes.hasContent == false)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesTextBinding: Binding<String> {
        Binding(
            get: { viewModel.recordingNotes.text },
            set: { text in
                viewModel.recordingNotes = RecordingNotes(
                    text: text,
                    isVisibleDuringRecording: viewModel.recordingNotes.isVisibleDuringRecording,
                    fontScale: viewModel.recordingNotes.fontScale
                )
            }
        )
    }

    private var notesVisibleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.recordingNotes.isVisibleDuringRecording },
            set: { isVisible in
                viewModel.recordingNotes = RecordingNotes(
                    text: viewModel.recordingNotes.text,
                    isVisibleDuringRecording: isVisible,
                    fontScale: viewModel.recordingNotes.fontScale
                )
            }
        )
    }

    private var notesFontScaleBinding: Binding<Double> {
        Binding(
            get: { viewModel.recordingNotes.fontScale },
            set: { fontScale in
                viewModel.recordingNotes = RecordingNotes(
                    text: viewModel.recordingNotes.text,
                    isVisibleDuringRecording: viewModel.recordingNotes.isVisibleDuringRecording,
                    fontScale: fontScale
                )
            }
        )
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
