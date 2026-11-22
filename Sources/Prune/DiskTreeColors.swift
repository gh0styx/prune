import SwiftUI

extension NodeKind {
    var color: Color {
        switch self {
        case .folder: Theme.blue
        case .app, .bundle: Theme.violet
        case .video, .audio, .image: Theme.pink
        case .archive, .diskImage: Theme.amber
        case .code: Theme.teal
        case .document: Theme.cyan
        case .other, .smallFiles, .system: Theme.gray
        }
    }

    private static let folderPalette: [Color] = [Theme.blue, Theme.violet, Theme.teal, Theme.cyan, Theme.pink, Theme.amber]

    /// Folders cycle through the palette so neighbours in the map stay distinct.
    func tint(_ index: Int) -> Color {
        self == .folder ? Self.folderPalette[index % Self.folderPalette.count] : color
    }
}
