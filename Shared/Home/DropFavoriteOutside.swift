import Foundation
import SwiftUI

struct DropFavoriteOutside: DropDelegate {
    @Binding var current: FavoriteItem?

    func performDrop(info _: DropInfo) -> Bool {
        current = nil
        return true
    }
}
