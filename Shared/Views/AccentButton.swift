import SwiftUI

struct AccentButton: View {
    var text: String?
    var imageSystemName: String?
    var maxWidth: CGFloat? = .infinity // swiftlint:disable:this no_cgfloat
    var bold = true
    var verticalPadding = 10.0
    var horizontalPadding = 10.0
    var minHeight = 45.0
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let imageSystemName {
                    Image(systemName: imageSystemName)
                }
                if let text {
                    Text(text.localized())
                        .fontWeight(bold ? .bold : .regular)
                }
            }
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .frame(maxWidth: maxWidth)
            .contentShape(Rectangle())
        }
        #if !os(tvOS)
        .foregroundColor(.accentColor)
        .buttonStyle(.plain)
        .background(buttonBackground)
        #endif
    }

    var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .foregroundColor(Color.accentColor.opacity(0.33))
    }
}

struct OpenVideosButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AccentButton(text: "Open Videos", imageSystemName: "play.circle.fill")
                .padding(.horizontal, 100)
            AccentButton(text: "Open Videos", imageSystemName: "play.circle.fill")
                .padding(.horizontal, 100)
        }
    }
}
