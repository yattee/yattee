import Repeat
import SwiftUI
import SwiftUIIntrospect

struct FocusableSearchTextField: View {
    var body: some View {
        SearchTextField()
        #if os(macOS)
            .introspect(.textField, on: .macOS(.v12, .v13, .v14, .v15)) { textField in
                SearchModel.shared.textField = textField
            }
            .onAppear {
                DispatchQueue.main.async {
                    SearchModel.shared.textField?.becomeFirstResponder()
                }
            }
        #endif
    }
}
