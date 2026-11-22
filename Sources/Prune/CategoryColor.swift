import SwiftUI

extension CategoryID {
    var color: Color {
        switch self {
        case .nodeModules: Theme.blue
        case .buildArtifacts: Theme.violet
        case .xcode: Theme.pink
        case .docker: Theme.cyan
        case .packageCaches: Theme.amber
        case .appCaches: Theme.teal
        case .messengerCaches: Theme.blue
        case .logs: Theme.gray
        case .downloads: Theme.green
        case .iosBackups: Theme.red
        case .largeFiles: Theme.muted
        case .apps: Theme.blue
        case .mailAttachments: Theme.cyan
        case .duplicates: Theme.violet
        case .security: Theme.green
        }
    }
}
