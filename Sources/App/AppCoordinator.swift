import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var activeProject: RecordingProject?
    @Published var isFloatingHomeToolbarPresented = true
    private var shouldRestoreFloatingHomeToolbarAfterRecording = false

    func open(project: RecordingProject) {
        shouldRestoreFloatingHomeToolbarAfterRecording = false
        isFloatingHomeToolbarPresented = false
        activeProject = project
    }

    func closeProject() {
        activeProject = nil
        isFloatingHomeToolbarPresented = true
    }

    func showHome() {
        activeProject = nil
        isFloatingHomeToolbarPresented = true
    }

    func presentFloatingHomeToolbar() {
        isFloatingHomeToolbarPresented = true
    }

    func dismissFloatingHomeToolbar() {
        shouldRestoreFloatingHomeToolbarAfterRecording = false
        isFloatingHomeToolbarPresented = false
    }

    func hideFloatingHomeToolbarForRecording() {
        shouldRestoreFloatingHomeToolbarAfterRecording = isFloatingHomeToolbarPresented
        isFloatingHomeToolbarPresented = false
    }

    func restoreFloatingHomeToolbarAfterRecordingInterruption() {
        guard shouldRestoreFloatingHomeToolbarAfterRecording else { return }
        shouldRestoreFloatingHomeToolbarAfterRecording = false
        isFloatingHomeToolbarPresented = true
    }
}
