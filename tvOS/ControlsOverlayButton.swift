import SwiftUI

struct ControlsOverlayButton<LabelView: View>: View {
    var focusedField: FocusState<ControlsOverlay.Field?>.Binding
    var field: ControlsOverlay.Field
    let label: LabelView
    var onSelect: (() -> Void)?

    init(
        focusedField: FocusState<ControlsOverlay.Field?>.Binding,
        field: ControlsOverlay.Field,
        onSelect: (() -> Void)? = nil,
        @ViewBuilder label: @escaping () -> LabelView
    ) {
        self.focusedField = focusedField
        self.field = field
        self.onSelect = onSelect
        self.label = label()
    }

    var body: some View {
        let isFocused = focusedField.wrappedValue == field

        if let onSelect {
            Button(action: onSelect) {
                label
                    .padding()
                    .frame(width: 400)
            }
            .buttonStyle(TVButtonStyle(isFocused: isFocused))
            .focused(focusedField, equals: field)
        } else {
            label
                .padding()
                .frame(width: 400)
                .focusable()
                .focused(focusedField, equals: field)
                .background(isFocused ? Color.white : Color.secondary)
                .foregroundColor(isFocused ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct TVButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isFocused ? Color.white : Color.secondary)
            .foregroundColor(isFocused ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
