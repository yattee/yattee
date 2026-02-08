//
//  TVSettingsButtonStyles.swift
//  Yattee
//
//  Button styles for tvOS settings forms - removes native glow effect.
//

#if os(tvOS)
import SwiftUI

// MARK: - Custom Picker for tvOS

/// Custom picker for tvOS that avoids the native focus glow effect
struct TVSettingsPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let content: () -> Content

    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(TVFormRowButtonStyle())

        if isExpanded {
            content()
        }
    }
}

// MARK: - Custom TextField for tvOS

/// Custom text field for tvOS that avoids the native focus glow effect
/// Uses a Button that shows an alert for text input
struct TVSettingsTextField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        Button {
            editText = text
            isEditing = true
        } label: {
            HStack {
                if text.isEmpty {
                    Text(title)
                        .foregroundStyle(.secondary)
                } else if isSecure {
                    Text(String(repeating: "•", count: min(text.count, 12)))
                        .foregroundStyle(.primary)
                } else {
                    Text(text)
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
        }
        .buttonStyle(TVFormRowButtonStyle())
        .alert(title, isPresented: $isEditing) {
            if isSecure {
                SecureField(title, text: $editText)
            } else {
                TextField(title, text: $editText)
            }
            Button("OK") {
                text = editText
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Button Styles

/// Button style for settings forms - subtle focus effect without glow
struct TVSettingsButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? .white.opacity(0.2) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Button style for toolbar Done/Cancel buttons - pill shaped like tvOS standard
struct TVToolbarButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(isFocused ? .white : .secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isFocused ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Custom toggle view for tvOS that replaces native Toggle to avoid glow effect
struct TVSettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(isOn ? "On" : "Off")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(TVFormRowButtonStyle())
    }
}

/// Button style for form rows (toggles, pickers) - matches form appearance
struct TVFormRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.15) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.01 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
