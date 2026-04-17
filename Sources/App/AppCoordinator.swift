import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var activeProject: RecordingProject?

    func open(project: RecordingProject) {
        activeProject = project
    }

    func closeProject() {
        activeProject = nil
    }

    func showHome() {
        activeProject = nil
    }
}
