import Foundation
import SwiftUI

struct FixtureEnvironmentObjectsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func injectFixtureEnvironmentObjects() -> some View {
        modifier(FixtureEnvironmentObjectsModifier())
    }
}
