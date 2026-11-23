import SwiftUI

extension Store {
    // MARK: Apps

    func loadApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        Task {
            let list = await Task.detached(priority: .userInitiated) { Scanner().scanApps() }.value
            withAnimation(.snappy(duration: 0.5)) {
                apps = list
                isLoadingApps = false
            }
        }
    }

    func uninstall(_ app: AppInfo) {
        requestClean([app.item] + app.leftovers)
    }

}
