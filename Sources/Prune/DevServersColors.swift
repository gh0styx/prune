import SwiftUI

extension DevServerKind {
    var color: Color {
        switch self {
        case .node: Theme.green
        case .bun: Theme.amber
        case .deno: Theme.teal
        case .python: Theme.blue
        case .ruby: Theme.red
        case .go: Theme.cyan
        case .java: Theme.amber
        case .php: Theme.violet
        case .rust: Theme.pink
        case .docker: Theme.blue
        case .database: Theme.violet
        case .other: Theme.gray
        }
    }
}
