import SwiftUI

struct SearchSuggestions: View {
    @ObservedObject private var state = SearchModel.shared

    var body: some View {
        List {
            if !state.queryText.isEmpty {
                Button {
                    runQueryAction(state.queryText)
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(state.queryText.trimmingCharacters(in: .whitespacesAndNewlines))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 5)

                #if os(macOS)
                    .onHover(perform: onHover(_:))
                #endif
            }

            ForEach(visibleSuggestions, id: \.self) { suggestion in
                HStack {
                    Button {
                        runQueryAction(suggestion)
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            HStack(spacing: 0) {
                                Text(suggestion)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                    .truncationMode(.head)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        state.queryText = suggestion
                    } label: {
                        Image(systemName: "arrow.up.left.circle")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .buttonStyle(.plain)
                }
                #if os(macOS)
                .onHover(perform: onHover(_:))
                #endif
            }
        }
        #if os(macOS)
        .buttonStyle(.link)
        #endif
    }

    private func runQueryAction(_ queryText: String) {
        state.queryText = queryText

        state.changeQuery { query in
            query.query = queryText
            NavigationModel.shared.hideKeyboard()
        }

        RecentsModel.shared.addQuery(queryText)
    }

    private var visibleSuggestions: [String] {
        state.querySuggestions.filter {
            $0.compare(state.queryText, options: .caseInsensitive) != .orderedSame
        }
    }

    #if os(macOS)
        private func onHover(_ inside: Bool) {
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    #endif
}

struct SearchSuggestions_Previews: PreviewProvider {
    static var previews: some View {
        SearchSuggestions()
            .injectFixtureEnvironmentObjects()
    }
}
