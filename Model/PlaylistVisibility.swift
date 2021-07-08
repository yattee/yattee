import Foundation

enum PlaylistVisibility: String, CaseIterable, Identifiable {
    case `public`, unlisted, `private`

    var id: String {
        rawValue
    }

    var name: String {
        rawValue.capitalized
    }
}
