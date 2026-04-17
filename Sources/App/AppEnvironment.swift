import Foundation

struct AppEnvironment {
    let preferencesStore: AppPreferencesStore
    let permissionManager: PermissionManager
    let screenRecorder: ScreenRecorder
    let eventMonitor: EventTapMonitor
    let cameraPlanEngine: CameraPlanEngine
    let projectStore: ProjectStore
    let videoRenderer: VideoRenderer
    let exportCoordinator: ExportCoordinator
    let hotkeyManager: HotkeyManager
    let windowController: AppWindowController
    let logger: Logger

    @MainActor
    static func live() -> AppEnvironment {
        let logger = Logger()
        let preferencesStore = AppPreferencesStore()
        let permissionManager = PermissionManager()
        let projectStore = ProjectStore()
        let eventStore = PointerEventStore()
        let eventMonitor = EventTapMonitor(store: eventStore)
        let cameraPlanEngine = CameraPlanEngine()
        let renderer = VideoRenderer()
        let exportCoordinator = ExportCoordinator(renderer: renderer, projectStore: projectStore)
        let hotkeyManager = HotkeyManager()
        let windowController = AppWindowController()
        let screenRecorder = ScreenRecorder(logger: logger)

        return AppEnvironment(
            preferencesStore: preferencesStore,
            permissionManager: permissionManager,
            screenRecorder: screenRecorder,
            eventMonitor: eventMonitor,
            cameraPlanEngine: cameraPlanEngine,
            projectStore: projectStore,
            videoRenderer: renderer,
            exportCoordinator: exportCoordinator,
            hotkeyManager: hotkeyManager,
            windowController: windowController,
            logger: logger
        )
    }
}
