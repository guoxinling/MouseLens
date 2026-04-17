import Foundation

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var permissions = AppPermissions.unknown

    private let permissionManager: PermissionManager

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        refresh()
    }

    func refresh() {
        permissions = permissionManager.currentPermissions()
    }
}
