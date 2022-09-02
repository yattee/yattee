import SwiftUI

struct ControlsOverlayButton<LabelView: View>: View {
    var focusedField: FocusState<ControlsOverlay.Field?>.Binding
    var field: ControlsOverlay.Field
    let label: LabelView

    init(
        focusedField: FocusState<ControlsOverlay.Field?>.Binding,
        field: ControlsOverlay.Field,
        @ViewBuilder label: @escaping () -> LabelView
    ) {
        self.focusedField = focusedField
        self.field = field
        self.label = label()
    }

    var body: some View {
        label
            .padding()
            .frame(width: 400)
            .focusable()
            .focused(focusedField, equals: field)
            .background(focusedField.wrappedValue == field ? Color.white : Color.secondary)
            .foregroundColor(focusedField.wrappedValue == field ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
