import SwiftUI

struct RedrawOnModifier: ViewModifier {
    @State private var changeFlag: Bool

    init(changeFlag: Bool) {
        self.changeFlag = changeFlag
    }

    func body(content: Content) -> some View {
        content.opacity(changeFlag ? 1 : 1)
    }
}

extension View {
    func redrawOn(change flag: Bool) -> some View {
        modifier(RedrawOnModifier(changeFlag: flag))
    }
}
