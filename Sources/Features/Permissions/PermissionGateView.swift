import AppKit
import SwiftUI

struct PermissionGateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var didAutoRequest = false
    @ObservedObject var viewModel: PermissionsViewModel
    let requiresMicrophone: Bool
    let onRequest: () -> Void
    let onGranted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions Required")
                .font(.title2.bold())
            Text(permissionExplanation)
                .foregroundStyle(AppTheme.mutedText)

            PermissionRow(label: "Screen Recording", status: viewModel.permissions.screenRecording)
            PermissionRow(label: "Microphone", status: viewModel.permissions.microphone, required: requiresMicrophone)
            PermissionRow(label: "Accessibility", status: viewModel.permissions.accessibility, required: false)

            HStack {
                Button("Close") {
                    dismiss()
                }

                Button("Refresh") {
                    handleRefresh()
                }

                Spacer()

                if recordingReady {
                    Button("Continue") {
                        completePermissionFlow()
                    }
                    .buttonStyle(.borderedProminent)
                } else if viewModel.permissions.needsScreenRecordingRelaunch {
                    Button("Quit MouseLens") {
                        quitApp()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Request Access", action: onRequest)
                        .buttonStyle(.borderedProminent)
                }
            }

            if viewModel.permissions.needsScreenRecordingRelaunch {
                Text("Screen Recording looks newly enabled, but macOS still requires you to quit and reopen MouseLens before capture becomes available to this process.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else if !requiresMicrophone && viewModel.permissions.microphone != .granted {
                Text("Microphone is off right now, so microphone permission will not block recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }

            if !viewModel.permissions.accessibility.isGranted {
                Text("Accessibility is optional. It only improves cursor-follow motion and should not block basic recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }

            Text("Detected now: Screen \(viewModel.permissions.screenRecording.rawValue), Microphone \(viewModel.permissions.microphone.rawValue), Accessibility \(viewModel.permissions.accessibility.rawValue)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(28)
        .onAppear {
            maybeAutoRequest()
        }
        .onChange(of: viewModel.permissions, initial: false) { _, permissions in
            guard permissions.recordingReady(requiresMicrophone: requiresMicrophone) else { return }
            completePermissionFlow()
        }
    }

    private func handleRefresh() {
        viewModel.refresh()
        if recordingReady {
            completePermissionFlow()
        }
    }

    private var recordingReady: Bool {
        viewModel.permissions.recordingReady(requiresMicrophone: requiresMicrophone)
    }

    private var permissionExplanation: String {
        if requiresMicrophone {
            return "MouseLens needs screen recording and microphone permissions to record. Accessibility only improves cursor-follow motion."
        }

        return "MouseLens needs screen recording permission to record. Accessibility and microphone are optional for this capture setup."
    }

    private func completePermissionFlow() {
        onGranted()
        dismiss()
    }

    private func quitApp() {
        dismiss()

        let currentApp = NSRunningApplication.current
        if !currentApp.terminate() {
            NSApplication.shared.terminate(nil)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !currentApp.isTerminated else { return }
            _ = currentApp.forceTerminate()
        }
    }

    private func maybeAutoRequest() {
        guard !didAutoRequest else { return }
        guard !recordingReady else { return }
        guard !viewModel.permissions.needsScreenRecordingRelaunch else { return }

        didAutoRequest = true
        onRequest()
    }
}

private struct PermissionRow: View {
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
