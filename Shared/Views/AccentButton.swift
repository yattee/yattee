import SwiftUI

struct AccentButton: View {
    var text: String?
    var imageSystemName: String?
    var maxWidth: CGFloat? = .infinity
    var bold = true
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
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(minHeight: 45)
            .frame(maxWidth: maxWidth)
            .contentShape(Rectangle())
        }
        .foregroundColor(.accentColor)
        .buttonStyle(.plain)
        .background(buttonBackground)
    }

    var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .foregroundColor(Color.accentColor.opacity(0.33))
    }
}

struct OpenVideosButton_Previews: PreviewProvider {
    static var previews: some View {
        AccentButton(text: "Open Videos", imageSystemName: "play.circle.fill")
    }
}
