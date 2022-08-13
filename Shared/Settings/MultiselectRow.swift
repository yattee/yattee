import SwiftUI

struct MultiselectRow: View {
    let title: String
    let selected: Bool
    var action: (Bool) -> Void

    @State private var toggleChecked = false

    var body: some View {
        Button(action: { action(!selected) }) {
            HStack {
                #if os(macOS)
                    Toggle(isOn: $toggleChecked) {
                        Text(self.title)
                        Spacer()
                    }
                    .onAppear {
                        toggleChecked = selected
                    }
                    .onChange(of: toggleChecked) { new in
                        action(new)
                    }
                #else
                    Text(self.title)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                        #if os(iOS)
                            .foregroundColor(.accentColor)
                        #endif
                    }
                #endif
            }
            .contentShape(Rectangle())
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
    }
}

struct MultiselectRow_Previews: PreviewProvider {
    static var previews: some View {
        MultiselectRow(title: "Title", selected: false, action: { _ in })
    }
}
