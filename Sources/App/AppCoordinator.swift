import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var activeProject: RecordingProject?
    @Published var isFloatingHomeToolbarPresented = true

    func open(project: RecordingProject) {
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
        isFloatingHomeToolbarPresented = false
    }
}
