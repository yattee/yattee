import SwiftUI

struct MultiselectRow: View {
    let title: String
    var selected: Bool
    var disabled = false
    var action: (Bool) -> Void

    @State private var toggleChecked = false

    var body: some View {
        #if os(tvOS)
            Button(action: { action(!selected) }) {
                HStack {
                    Text(self.title)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(disabled)
        #else
            Toggle(title, isOn: $toggleChecked)
            #if os(macOS)
                .toggleStyle(.checkbox)
            #endif
                .onAppear {
                    guard !disabled else { return }
                    toggleChecked = selected
                }
                .onChange(of: toggleChecked) { new in
                    action(new)
                }
        #endif
    }
}

struct MultiselectRow_Previews: PreviewProvider {
    static var previews: some View {
        MultiselectRow(title: "Title", selected: false) { _ in }
    }
}
