import Defaults
import SwiftUI

struct DetailBadge: View {
    enum Style {
        case `default`, prominent, outstanding, informational
    }

    struct StyleModifier: ViewModifier {
        let style: Style

        func body(content: Content) -> some View {
            Group {
                switch style {
                case .prominent:
                    content.modifier(ProminentStyleModifier())
                case .outstanding:
                    content.modifier(OutstandingStyleModifier())
                case .informational:
                    content.modifier(InformationalStyleModifier())
                default:
                    content.modifier(DefaultStyleModifier())
                }
            }
        }
    }

    struct DefaultStyleModifier: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            content
                .modifier(ControlBackgroundModifier())
        }
    }

    struct ProminentStyleModifier: ViewModifier {
        var font: Font {
            Font.system(.body).weight(.semibold)
        }

        func body(content: Content) -> some View {
            content
                .font(font)
                .modifier(DefaultStyleModifier())
        }
    }

    struct OutstandingStyleModifier: ViewModifier {
        var backgroundColor: Color {
            Color("DetailBadgeOutstandingStyleBackgroundColor")
        }

        func body(content: Content) -> some View {
            content
                .textCase(.uppercase)
                .background(backgroundColor)
                .foregroundColor(.white)
        }
    }

    struct InformationalStyleModifier: ViewModifier {
        var backgroundColor: Color {
            Color("DetailBadgeInformationalStyleBackgroundColor")
        }

        func body(content: Content) -> some View {
            content
                .background(backgroundColor)
                .foregroundColor(.white)
        }
    }

    var text: String
    var style: Style = .default

    @Default(.roundedThumbnails) private var roundedThumbnails

    var body: some View {
        Text(text)
            .truncationMode(.middle)
            .padding(4)
        #if os(tvOS)
            .padding(.horizontal, 5)
        #endif
            .modifier(StyleModifier(style: style))
            .mask(RoundedRectangle(cornerRadius: roundedThumbnails ? 6 : 0))
    }
}

struct DetailBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            DetailBadge(text: "Live", style: .outstanding)
            DetailBadge(text: "Premieres", style: .informational)
            DetailBadge(text: "Booyah", style: .prominent)
            DetailBadge(
                text: "Donec in neque mi. Phasellus quis sapien metus. Ut felis ante, posuere."
            )
        }
        .frame(maxWidth: 500)
    }
}
