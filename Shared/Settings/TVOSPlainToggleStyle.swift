import SwiftUI

#if os(tvOS)
    struct TVOSPlainToggleStyle: ToggleStyle {
        func makeBody(configuration: Configuration) -> some View {
            Button(action: { configuration.isOn.toggle() }) {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
#endif
