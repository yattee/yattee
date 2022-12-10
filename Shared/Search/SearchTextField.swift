import Repeat
import SwiftUI

struct SearchTextField: View {
    private var navigation = NavigationModel.shared
    @ObservedObject private var state = SearchModel.shared

    var body: some View {
        ZStack {
            #if os(macOS)
                fieldBorder
            #endif

            HStack(spacing: 0) {
                #if os(macOS)
                    Image(systemName: "magnifyingglass")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 12, height: 12)
                        .padding(.horizontal, 8)
                        .opacity(0.8)
                #endif
                TextField("Search...", text: $state.queryText) {
                    state.changeQuery { query in
                        query.query = state.queryText
                        navigation.hideKeyboard()
                    }
                    RecentsModel.shared.addQuery(state.queryText)
                }
                .disableAutocorrection(true)
                #if os(macOS)
                    .frame(maxWidth: 190)
                    .textFieldStyle(.plain)
                #else
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 5)
                    .padding(.trailing, 10)
                #endif

                if !state.queryText.isEmpty {
                    clearButton
                } else {
                    #if os(macOS)
                        clearButton
                            .opacity(0)
                    #endif
                }
            }
        }
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.background)
            .frame(width: 250, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    .frame(width: 250, height: 31)
            )
    }

    private var clearButton: some View {
        Button(action: {
            self.state.queryText = ""
        }) {
            Image(systemName: "xmark.circle.fill")
            #if os(macOS)
                .imageScale(.small)
            #else
                .imageScale(.medium)
            #endif
        }
        .buttonStyle(PlainButtonStyle())
        #if os(macOS)
            .padding(.trailing, 10)
        #endif
            .opacity(0.7)
    }
}
