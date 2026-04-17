import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onProjectReady: (RecordingProject) -> Void

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 24) {
                hero
                captureCard
                recentProjectsCard
            }
            .frame(maxWidth: 420, alignment: .topLeading)

            VStack(spacing: 24) {
                featureBoard

                switch viewModel.recordingState {
                case .idle:
                    idleBoard
                case .countdown, .recording:
                    RecordingHUDView(
                        state: viewModel.recordingState,
                        shortcutHint: viewModel.recordingShortcutHint,
                        onPrimaryAction: {
                            Task {
                                switch viewModel.recordingState {
                                case .countdown:
                                    viewModel.cancelCountdown()
                                case .recording:
                                    await viewModel.stopRecording()
                                case .idle:
                                    await viewModel.startRecording()
                                }
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(32)
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
            viewModel.loadRecentProjects()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("MouseLens")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Spacer()

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            Text("Record a walkthrough. Get the camera work for free.")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedText)

            if viewModel.permissions.needsScreenRecordingRelaunch {
                Text("Screen Recording was enabled, but MouseLens must be quit and reopened before macOS will allow capture.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            if !viewModel.permissions.accessibility.isGranted {
                Text("Accessibility is optional in this build. Recording can continue, but cursor-follow quality may be reduced.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingRow("Capture Mode") {
                Picker("Capture Target", selection: $viewModel.selectedCaptureTarget) {
                    ForEach(CaptureTarget.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingRow("Audio") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Microphone", isOn: $viewModel.includeMicrophone)
                    Toggle("System Audio", isOn: $viewModel.includeSystemAudio)
                }
                .toggleStyle(.switch)
            }

            SettingRow("Output") {
                Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                    ForEach(ProjectAspectRatio.allCases, id: \.self) { ratio in
                        Text(ratio.label).tag(ratio)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.startRecording() }
                } label: {
                    Label(startButtonTitle, systemImage: startButtonIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.recordingState != .idle)

                Button("Refresh Permissions") {
                    viewModel.refreshPermissions()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.recordingState != .idle)
            }

            Text("Shortcut: \(viewModel.recordingShortcutHint) to start, cancel, or stop from anywhere.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)

            if viewModel.permissions.needsScreenRecordingRelaunch {
                Text("Screen Recording is waiting on an app relaunch. Quit MouseLens, reopen it, then try again.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            permissionSummary
        }
        .cardStyle()
    }

    private var startButtonTitle: String {
        viewModel.permissions.needsScreenRecordingRelaunch ? "Reopen Required" : "Start Recording"
    }

    private var startButtonIcon: String {
        viewModel.permissions.needsScreenRecordingRelaunch ? "arrow.clockwise.circle.fill" : "record.circle.fill"
    }

    private var permissionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.headline)
            PermissionRow(label: "Screen Recording", status: viewModel.permissions.screenRecording)
            PermissionRow(label: "Microphone", status: viewModel.permissions.microphone, required: viewModel.includeMicrophone)
            PermissionRow(label: "Accessibility", status: viewModel.permissions.accessibility, required: false)
        }
    }

    private var recentProjectsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Projects")
                .font(.headline)

            if viewModel.recentProjects.isEmpty {
                Text("No local projects yet. Your first recording will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(viewModel.recentProjects) { project in
                    Button {
                        onProjectReady(viewModel.openRecent(project: project))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(project.style.aspectRatio.label)
                                .font(.caption)
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(AppTheme.panelBorder.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .cardStyle()
    }

    private var featureBoard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MVP Focus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("A tiny recording workflow, not a traditional editor.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("MouseLens stays intentionally narrow: capture the screen, track the pointer, generate polished camera motion, and export fast.")
                .foregroundStyle(AppTheme.mutedText)

            HStack(spacing: 16) {
                FeaturePill(title: "Local-first", subtitle: "No cloud required")
                FeaturePill(title: "Auto motion", subtitle: "Cursor + click driven")
                FeaturePill(title: "Fast export", subtitle: "Real MP4 compositing")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.heroGradient)
        )
    }

    private var idleBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to record")
                .font(.title2.bold())
            Text("When recording starts, MouseLens will keep a raw session, collect pointer activity, and convert it into a reusable motion plan.")
                .foregroundStyle(AppTheme.mutedText)

            VStack(alignment: .leading, spacing: 10) {
                Text("Current defaults")
                    .font(.headline)
                Text("• \(viewModel.selectedCaptureTarget.label)")
                Text("• \(viewModel.selectedAspectRatio.label)")
                Text("• Microphone \(viewModel.includeMicrophone ? "on" : "off")")
                Text("• System audio \(viewModel.includeSystemAudio ? "on" : "off")")
            }
            .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
        .cardStyle()
    }
}

struct PermissionRow: View {
    let label: String
    let status: PermissionStatus
    var required: Bool = true

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(label)
            if !required {
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            } else if status == .requiresRelaunch {
                Text("Restart Needed")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
    }

    private var iconName: String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .requiresRelaunch:
            return "arrow.clockwise.circle.fill"
        case .denied, .unknown:
            return required ? "xmark.circle.fill" : "minus.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .granted:
            return .green
        case .requiresRelaunch:
            return .orange
        case .denied, .unknown:
            return required ? .orange : AppTheme.mutedText
        }
    }
}

private struct FeaturePill: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
