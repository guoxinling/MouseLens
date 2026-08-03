import AppKit
import SwiftUI

@MainActor
@main
struct MouseLensApp: App {
    @NSApplicationDelegateAdaptor(MouseLensAppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var editorViewModel: EditorViewModel
    @StateObject private var preferencesStore: AppPreferencesStore

    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.live()
        let coordinator = AppCoordinator()
        let homeViewModel = HomeViewModel(environment: environment)
        self.environment = environment
        _coordinator = StateObject(wrappedValue: coordinator)
        _homeViewModel = StateObject(wrappedValue: homeViewModel)
        _preferencesStore = StateObject(wrappedValue: environment.preferencesStore)
        _editorViewModel = StateObject(
            wrappedValue: EditorViewModel(
                exportCoordinator: environment.exportCoordinator,
                previewRenderer: environment.videoRenderer,
                cameraPlanEngine: environment.cameraPlanEngine,
                projectStore: environment.projectStore,
                preferencesStore: environment.preferencesStore
            )
        )

        environment.windowController.onCaptureSetupPanelDismissed = {
            coordinator.dismissFloatingHomeToolbar()
        }

        MouseLensAppDelegate.openCaptureToolbarHandler = {
            if coordinator.activeProject != nil {
                environment.windowController.activateAppWindow(forceAppActivation: true)
                return
            }
            coordinator.presentFloatingHomeToolbar()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                coordinator: coordinator,
                homeViewModel: homeViewModel,
                editorViewModel: editorViewModel,
                preferences: preferencesStore,
                windowController: environment.windowController
            )
            .mouseLensAppLocale(preferencesStore.appLanguage)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(
                preferences: environment.preferencesStore,
                shortcutLabel: homeViewModel.recordingShortcutHint
            )
            .mouseLensAppLocale(preferencesStore.appLanguage)
        }

        MenuBarExtra("MouseLens", systemImage: menuBarSymbolName) {
            MenuBarCaptureView(
                coordinator: coordinator,
                viewModel: homeViewModel,
                windowController: environment.windowController
            )
            .mouseLensAppLocale(preferencesStore.appLanguage)
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

private struct MenuBarCaptureView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var viewModel: HomeViewModel
    let windowController: AppWindowController

    var body: some View {
        Text(viewModel.captureConfigurationSummary)

        Button {
            Task { await viewModel.handleRecordingToggleHotkey() }
        } label: {
            Text(LocalizedStringKey(viewModel.menuBarPrimaryActionTitle))
        }
        .disabled(viewModel.isRecordingActionDisabled)

        if case .recording(let session) = viewModel.recordingState {
            Button {
                viewModel.toggleRecordingPause()
            } label: {
                Text(LocalizedStringKey(session.isPaused ? "Resume Recording" : "Pause Recording"))
            }
        }

        if viewModel.recordingState == .idle {
            Divider()

            Menu("Capture Target") {
                ForEach(CaptureTarget.allCases, id: \.self) { target in
                    Button {
                        viewModel.selectedCaptureTarget = target
                    } label: {
                        Label(
                            LocalizedStringKey(target.label),
                            systemImage: viewModel.selectedCaptureTarget == target
                                ? "checkmark"
                                : captureTargetSymbol(for: target)
                        )
                    }
                }
            }

            if viewModel.selectedCaptureTarget == .window {
                Menu("Window: \(viewModel.selectedWindowTargetLabel)") {
                    Button {
                        Task { await viewModel.refreshWindowTargets() }
                    } label: {
                        Label("Refresh Windows", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    if viewModel.availableWindowTargets.isEmpty {
                        Text("No recordable windows")
                    } else {
                        ForEach(viewModel.availableWindowTargets) { target in
                            Button {
                                viewModel.selectWindowTarget(target)
                            } label: {
                                Label(
                                    target.displayLabel,
                                    systemImage: target.id == viewModel.selectedWindowTargetID
                                        ? "checkmark"
                                        : "macwindow"
                                )
                            }
                        }
                    }
                }
            }

            Toggle("Microphone", isOn: $viewModel.includeMicrophone)
            Toggle("System Audio", isOn: $viewModel.includeSystemAudio)

            Menu("Aspect Ratio: \(viewModel.selectedAspectRatio.label)") {
                ForEach(ProjectAspectRatio.allCases, id: \.self) { ratio in
                    Button {
                        viewModel.selectedAspectRatio = ratio
                    } label: {
                        Label(
                            LocalizedStringKey(ratio.label),
                            systemImage: viewModel.selectedAspectRatio == ratio
                                ? "checkmark"
                                : "rectangle"
                        )
                    }
                }
            }
        }

        Divider()

        if coordinator.activeProject != nil {
            Button("Open Editor") {
                windowController.activateAppWindow(forceAppActivation: true)
            }
        } else {
            Button("Open Capture Toolbar") {
                coordinator.presentFloatingHomeToolbar()
            }
        }

        if coordinator.activeProject != nil {
            Button("Back to Home") {
                coordinator.showHome()
                windowController.activateAppWindow(forceAppActivation: true)
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

    private func captureTargetSymbol(for target: CaptureTarget) -> String {
        switch target {
        case .screen:
            return "display"
        case .window:
            return "macwindow"
        }
    }
}

@MainActor
final class MouseLensAppDelegate: NSObject, NSApplicationDelegate {
    static var openCaptureToolbarHandler: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if sender.windows.contains(where: { $0.contentLayoutRect.height <= 120 }) {
            Self.openCaptureToolbarHandler?()
            return false
        }

        guard !flag else { return true }

        if let window = sender.windows.first(where: { window in
            window.canBecomeKey && !window.isMiniaturized
        }) {
            sender.unhide(nil)
            if window.contentLayoutRect.height <= 120 {
                window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
                window.level = .floating
                window.sharingType = .none
                window.orderFrontRegardless()
            } else {
                window.makeKeyAndOrderFront(nil)
            }
            sender.activate(ignoringOtherApps: true)
            return false
        }

        Self.openCaptureToolbarHandler?()
        return false
    }
}

enum HomeToolbarPresentationMode: Equatable {
    case primaryWindow
    case floatingPanel

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        environment["XCTestConfigurationFilePath"] == nil ? .floatingPanel : .primaryWindow
    }

    var rendersIntoPrimaryWindow: Bool {
        self == .primaryWindow
    }
}

private struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var preferences: AppPreferencesStore
    let windowController: AppWindowController

    private var homeToolbarPresentationMode: HomeToolbarPresentationMode {
        HomeToolbarPresentationMode.current()
    }

    private var homeToolbarRendersIntoPrimaryWindow: Bool {
        homeToolbarPresentationMode.rendersIntoPrimaryWindow
    }

    private var primaryWindowWidth: CGFloat {
        coordinator.activeProject == nil && !homeToolbarRendersIntoPrimaryWindow ? 1 : 1120
    }

    private var primaryWindowHeight: CGFloat {
        if coordinator.activeProject != nil {
            return 720
        }
        return homeToolbarRendersIntoPrimaryWindow ? 96 : 1
    }

    var body: some View {
        ZStack {
            AppTheme.windowBackground.ignoresSafeArea()

            if let project = coordinator.activeProject {
                EditorView(
                    viewModel: editorViewModel,
                    project: project,
                    onBack: { coordinator.closeProject() }
                )
            } else if homeToolbarRendersIntoPrimaryWindow {
                HomeView(
                    viewModel: homeViewModel,
                    onProjectReady: { project in
                        coordinator.open(project: project)
                    }
                )
                .mouseLensAppLocale(preferences.appLanguage)
            } else {
                Color.clear
            }
        }
        .background(
            WindowAccessor { window in
                windowController.attachAppWindow(window)
                configureWindowForCurrentMode()
            }
        )
        .frame(
            minWidth: primaryWindowWidth,
            idealWidth: primaryWindowWidth,
            maxWidth: .infinity,
            minHeight: primaryWindowHeight,
            idealHeight: primaryWindowHeight,
            maxHeight: coordinator.activeProject == nil ? primaryWindowHeight : .infinity
        )
        .onAppear {
            configureWindowForCurrentMode()
        }
        .onChange(of: coordinator.activeProject?.id) { _, _ in
            configureWindowForCurrentMode()
        }
        .onChange(of: coordinator.isFloatingHomeToolbarPresented) { _, _ in
            configureWindowForCurrentMode()
        }
        .onChange(of: homeViewModel.recordingState, initial: true) { _, state in
            switch state {
            case .idle:
                if coordinator.activeProject == nil, homeViewModel.completedProject == nil {
                    coordinator.restoreFloatingHomeToolbarAfterRecordingInterruption()
                }
            case .countdown, .recording:
                coordinator.hideFloatingHomeToolbarForRecording()
            }
            updateRecordingControlPanel(for: state)
        }
        .onChange(of: homeViewModel.completedProject?.id) { _, _ in
            guard let project = homeViewModel.completedProject else { return }
            coordinator.open(project: project)
            homeViewModel.consumeCompletedProject()
            Task { @MainActor in
                await Task.yield()
                windowController.restoreAfterCapture(activate: false)
                windowController.applyEditorWindowLayout()
                windowController.maximizeEditorWindowOnActiveScreen()
                windowController.activateAppWindow(forceAppActivation: true)
            }
        }
    }

    private func configureWindowForCurrentMode() {
        Task { @MainActor in
            await Task.yield()

            if coordinator.activeProject == nil {
                if homeToolbarRendersIntoPrimaryWindow {
                    windowController.hideCaptureSetupPanel()
                    windowController.applyHomeToolbarWindowLayout()
                } else {
                    windowController.hidePrimaryWindowForFloatingHomeToolbar()
                    if coordinator.isFloatingHomeToolbarPresented {
                        if !windowController.isCaptureSetupPanelVisible {
                            windowController.showCaptureSetupPanel {
                                HomeView(
                                    viewModel: homeViewModel,
                                    onProjectReady: { project in
                                        coordinator.open(project: project)
                                    }
                                )
                                .mouseLensAppLocale(preferences.appLanguage)
                            }
                        }
                    } else {
                        windowController.hideCaptureSetupPanel()
                    }
                }
            } else {
                windowController.hideCaptureSetupPanel()
                windowController.applyEditorWindowLayout()
                windowController.activateAppWindow()
            }
        }
    }

    private func updateRecordingControlPanel(for state: RecordingState) {
        updateRecordingNotesPanel(for: state)

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
            let contentSize = FloatingRecordingToolbarView.contentSize(hasPresenterPreview: false)
            windowController.showRecordingControlPanel(contentSize: contentSize) {
                FloatingRecordingToolbarView(
                    session: session,
                    presenterPreviewSession: nil,
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

    private func updateRecordingNotesPanel(for state: RecordingState) {
        guard let notes = HomeViewModel.recordingNotesOverlayPayload(
            from: homeViewModel.recordingNotes,
            recordingState: state
        ) else {
            windowController.hideRecordingNotesPanel()
            return
        }

        let contentSize = FloatingRecordingNotesView.contentSize(for: notes)
        windowController.showRecordingNotesPanel(contentSize: contentSize) {
            FloatingRecordingNotesView(notes: notes)
        }
    }
}

private extension View {
    @ViewBuilder
    func mouseLensAppLocale(_ language: AppLanguagePreference) -> some View {
        if let localeIdentifier = language.localeIdentifier {
            environment(\.locale, Locale(identifier: localeIdentifier))
        } else {
            self
        }
    }
}

private struct FloatingRecordingNotesView: View {
    static let baseWidth: CGFloat = 420
    static let baseHeight: CGFloat = 132

    let notes: RecordingNotes

    static func contentSize(for notes: RecordingNotes) -> NSSize {
        NSSize(
            width: baseWidth * CGFloat(notes.fontScale.clamped(to: 0.8...1.6)),
            height: baseHeight * CGFloat(notes.fontScale.clamped(to: 0.8...1.6))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 15 * notes.fontScale, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text("Notes")
                    .font(.system(size: 14 * notes.fontScale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Text(notes.text)
                .font(.system(size: 18 * notes.fontScale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18 * notes.fontScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
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
