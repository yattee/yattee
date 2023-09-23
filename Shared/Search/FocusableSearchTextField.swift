import Introspect
import Repeat
import SwiftUI

struct FocusableSearchTextField: View {
    @ObservedObject private var state = SearchModel.shared

    #if os(iOS)
        @State private var textField: UITextField?
    #elseif os(macOS)
        @State private var textField: NSTextField?
    #endif

    var body: some View {
        SearchTextField()
        #if os(iOS)
            .introspectTextField { field in
                textField = field
            }
            .onChange(of: state.focused) { newValue in
                if newValue, let textField, !textField.isFirstResponder {
                    textField.becomeFirstResponder()
                    textField.selectedTextRange = textField.textRange(from: textField.beginningOfDocument, to: textField.endOfDocument)
                }
            }
        #endif
    }
}
