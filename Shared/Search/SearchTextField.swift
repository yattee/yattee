import SwiftUI

struct SearchTextField: View {
    private var navigation = NavigationModel.shared
    @ObservedObject private var state = SearchModel.shared

    #if os(macOS)
        var body: some View {
            ZStack {
                fieldBorder

                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 12, height: 12)
                        .padding(.horizontal, 6)
                        .opacity(0.8)

                    GeometryReader { geometry in
                        TextField("Search...", text: $state.queryText) {
                            state.changeQuery { query in
                                query.query = state.queryText
                                navigation.hideKeyboard()
                            }
                            RecentsModel.shared.addQuery(state.queryText)
                        }
                        .disableAutocorrection(true)
                        .frame(maxWidth: geometry.size.width - 5)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 8)
                        .frame(height: 27, alignment: .center)
                    }

                    if !state.queryText.isEmpty {
                        clearButton
                    } else {
                        clearButton
                            .opacity(0)
                    }
                }
            }
            .transaction { t in t.animation = nil }
        }
    #else
        var body: some View {
            ZStack {
                HStack {
                    HStack(spacing: 0) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .padding(.leading, 5)
                            .padding(.trailing, 5)
                            .imageScale(.medium)

                        TextField("Search...", text: $state.queryText) {
                            state.changeQuery { query in
                                query.query = state.queryText
                                navigation.hideKeyboard()
                            }
                            RecentsModel.shared.addQuery(state.queryText)
                        }
                        .disableAutocorrection(true)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 7)

                        if !state.queryText.isEmpty {
                            clearButton
                                .padding(.leading, 5)
                                .padding(.trailing, 5)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color("SearchTextFieldBackground"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 0)
            }
            .transaction { t in t.animation = nil }
        }
    #endif

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.background)
            .frame(width: 250, height: 27)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    .frame(width: 250, height: 27)
            )
    }

    private var clearButton: some View {
        Button(action: {
            self.state.queryText = ""
        }) {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.medium)
        }
        .buttonStyle(PlainButtonStyle())
        #if os(macOS)
            .padding(.trailing, 5)
        #elseif os(iOS)
            .padding(.trailing, 5)
            .foregroundColor(.gray)
        #endif
            .opacity(0.7)
    }
}
