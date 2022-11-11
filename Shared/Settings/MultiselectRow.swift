import SwiftUI

struct MultiselectRow: View {
    let title: String
    var selected: Bool
    var disabled = false
    var action: (Bool) -> Void

    @State private var toggleChecked = false

    var body: some View {
        #if os(macOS)
            Toggle(title, isOn: $toggleChecked)
                .toggleStyle(.checkbox)
                .onAppear {
                    guard !disabled else { return }
                    toggleChecked = selected
                }
                .onChange(of: toggleChecked) { new in
                    action(new)
                }
        #else
            Button(action: { action(!selected) }) {
                HStack {
                    Text(self.title)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                        #if os(iOS)
                            .foregroundColor(.accentColor)
                        #endif
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(disabled)
            #if !os(tvOS)
                .buttonStyle(.plain)
            #endif
        #endif
    }
}

struct MultiselectRow_Previews: PreviewProvider {
    static var previews: some View {
        MultiselectRow(title: "Title", selected: false) { _ in }
    }
}
