import AppKit
import SwiftUI

@MainActor
@main
struct MouseLensApp: App {
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
                editorViewModel: editorViewModel
            )
            .frame(minWidth: 1120, minHeight: 720)
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
        case .recording:
            return "stop.circle.fill"
        }
    }
}

private struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var editorViewModel: EditorViewModel

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
        .onChange(of: homeViewModel.completedProject?.id) { _, _ in
            guard let project = homeViewModel.completedProject else { return }
            coordinator.open(project: project)
            homeViewModel.consumeCompletedProject()
        }
    }
}
