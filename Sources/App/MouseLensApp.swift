import AppKit
import SwiftUI

@MainActor
@main
struct MouseLensApp: App {
    @NSApplicationDelegateAdaptor(MouseLensAppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var editorViewModel: EditorViewModel

    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.live()
        self.environment = environment
        _coordinator = StateObject(wrappedValue: AppCoordinator())
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(environment: environment))
        _editorViewModel = StateObject(
            wrappedValue: EditorViewModel(
                exportCoordinator: environment.exportCoordinator,
                previewRenderer: environment.videoRenderer,
                cameraPlanEngine: environment.cameraPlanEngine,
                projectStore: environment.projectStore,
                preferencesStore: environment.preferencesStore
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                coordinator: coordinator,
                homeViewModel: homeViewModel,
                editorViewModel: editorViewModel,
                windowController: environment.windowController
            )
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(
                preferences: environment.preferencesStore,
                shortcutLabel: homeViewModel.recordingShortcutHint
            )
        }

        MenuBarExtra("MouseLens", systemImage: menuBarSymbolName) {
            Button(homeViewModel.menuBarPrimaryActionTitle) {
                Task { await homeViewModel.handleRecordingToggleHotkey() }
            }

            Divider()

            Button("Open MouseLens") {
                environment.windowController.activateAppWindow()
            }

            if coordinator.activeProject != nil {
                Button("Back to Home") {
                    coordinator.showHome()
                    environment.windowController.activateAppWindow()
                }
            }

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var menuBarSymbolName: String {
        switch homeViewModel.recordingState {
        case .idle:
            return "record.circle"
        case .countdown:
            return "timer.circle"
        case .recording(let session):
            return session.isPaused ? "pause.circle.fill" : "stop.circle.fill"
        }
    }
}

final class MouseLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        if let window = sender.windows.first(where: { window in
            window.canBecomeKey && !window.isMiniaturized
        }) {
            sender.unhide(nil)
            sender.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return false
        }

        return true
    }
}

private struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    let windowController: AppWindowController

    var body: some View {
        ZStack {
            AppTheme.windowBackground.ignoresSafeArea()

            if let project = coordinator.activeProject {
                EditorView(
                    viewModel: editorViewModel,
                    project: project,
                    onBack: { coordinator.closeProject() }
                )
            } else {
                HomeView(
                    viewModel: homeViewModel,
                    onProjectReady: { project in
                        coordinator.open(project: project)
                    }
                )
            }
        }
        .background(
            WindowAccessor { window in
                windowController.attachAppWindow(window)
                configureWindowForCurrentMode()
            }
        )
        .frame(
            minWidth: 1120,
            idealWidth: 1120,
            maxWidth: .infinity,
            minHeight: coordinator.activeProject == nil ? 96 : 720,
            idealHeight: coordinator.activeProject == nil ? 96 : 720,
            maxHeight: coordinator.activeProject == nil ? 96 : .infinity
        )
        .onAppear {
            configureWindowForCurrentMode()
        }
        .onChange(of: coordinator.activeProject?.id) { _, _ in
            configureWindowForCurrentMode()
        }
        .onChange(of: homeViewModel.recordingState, initial: true) { _, state in
            updateRecordingControlPanel(for: state)
        }
        .onChange(of: homeViewModel.completedProject?.id) { _, _ in
            guard let project = homeViewModel.completedProject else { return }
            coordinator.open(project: project)
            homeViewModel.consumeCompletedProject()
            Task { @MainActor in
                await Task.yield()
                windowController.restoreAfterCapture()
                windowController.activateAppWindow()
            }
        }
    }

    private func configureWindowForCurrentMode() {
        Task { @MainActor in
            await Task.yield()

            if coordinator.activeProject == nil {
                windowController.applyHomeToolbarWindowLayout()
            } else {
                windowController.applyEditorWindowLayout()
            }
        }
    }

    private func updateRecordingControlPanel(for state: RecordingState) {
        switch state {
        case .idle:
            windowController.hideRecordingControlPanel()
        case .countdown(let secondsRemaining):
            windowController.showRecordingControlPanel {
                FloatingCountdownToolbarView(
                    secondsRemaining: secondsRemaining,
                    shortcutHint: homeViewModel.recordingShortcutHint,
                    onCancel: {
                        homeViewModel.cancelCountdown()
                    }
                )
            }
        case .recording(let session):
            windowController.showRecordingControlPanel {
                FloatingRecordingToolbarView(
                    session: session,
                    onPauseResume: {
                        homeViewModel.toggleRecordingPause()
                    },
                    onStop: {
                        Task { await homeViewModel.stopRecording() }
                    }
                )
            }

        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindow(for: nsView)
    }

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
        }
    }
}
