#if os(iOS)
    import ActiveLabel
#endif
import Defaults
import Foundation
import SwiftUI

struct VideoDescription: View {
    private var search: SearchModel { .shared }
    @Default(.showKeywords) private var showKeywords
    @Default(.expandVideoDescription) private var expandVideoDescription
    @Default(.collapsedLinesDescription) private var collapsedLinesDescription

    var video: Video
    var detailsSize: CGSize?
    @Binding var expand: Bool

    var description: String {
        video.description ?? ""
    }

    var body: some View {
        descriptionView.id(video.videoID)
    }

    @ViewBuilder var descriptionView: some View {
        if !expand && collapsedLinesDescription == 0 {
            EmptyView()
        } else {
            VStack {
                #if os(iOS)
                    ActiveLabelDescriptionRepresentable(
                        description: description,
                        detailsSize: detailsSize,
                        expand: expand
                    )
                #else
                    textDescription
                #endif

                keywords
            }
            .contentShape(Rectangle())
            .overlay(
                Group {
                    #if canImport(UIKit)
                        if !expand {
                            Button(action: { expand.toggle() }) {
                                Rectangle()
                                    .foregroundColor(.clear)
                            }
                        }
                    #endif
                }
            )
        }
    }

    @ViewBuilder var textDescription: some View {
        #if canImport(AppKit)
            Group {
                if #available(macOS 12, *) {
                    DescriptionWithLinks(description: description, detailsSize: detailsSize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(expand ? 500 : collapsedLinesDescription)
                        .textSelection(.enabled)
                } else {
                    Text(description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(expand ? 500 : collapsedLinesDescription)
                }
            }
            .multilineTextAlignment(.leading)
            .font(.system(size: 14))
            .lineSpacing(3)
            .allowsHitTesting(expand)
        #endif
    }

    // If possibe convert URLs to clickable links
    #if canImport(AppKit)
        @available(macOS 12, *)
        struct DescriptionWithLinks: View {
            let description: String
            let detailsSize: CGSize?
            let separators = CharacterSet(charactersIn: " \n")

            var formattedString: AttributedString {
                var attrString = AttributedString(description)
                let words = description.unicodeScalars.split(whereSeparator: separators.contains).map(String.init)
                for word in words {
                    if word.hasPrefix("https://") || word.hasPrefix("http://"), let url = URL(string: String(word)) {
                        if let range = attrString.range(of: word) {
                            attrString[range].link = url
                        }
                    }
                }
                return attrString
            }

            var body: some View {
                Text(formattedString)
            }
        }
    #endif

    @ViewBuilder var keywords: some View {
        if showKeywords {
            ScrollView(.horizontal, showsIndicators: showScrollIndicators) {
                HStack {
                    ForEach(video.keywords, id: \.self) { keyword in
                        Button {
                            NavigationModel.shared.openSearchQuery(keyword)
                        } label: {
                            HStack(spacing: 0) {
                                Text("#")
                                    .font(.system(size: 14).bold())

                                Text(keyword)
                                    .frame(maxWidth: 500)
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color("KeywordBackgroundColor"))
                            .mask(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var showScrollIndicators: Bool {
        #if canImport(AppKit)
            false
        #else
            true
        #endif
    }
}

#if os(iOS)
    struct ActiveLabelDescriptionRepresentable: UIViewRepresentable {
        var description: String
        var detailsSize: CGSize?
        var expand: Bool

        @State private var label = ActiveLabel()

        @Environment(\.openURL) private var openURL

        @Default(.collapsedLinesDescription) private var collapsedLinesDescription

        var player = PlayerModel.shared

        func makeUIView(context _: Context) -> some UIView {
            customizeLabel()
            return label
        }

        func updateUIView(_: UIViewType, context _: Context) {
            updatePreferredMaxLayoutWidth()
            updateNumberOfLines()
        }

        func customizeLabel() {
            label.customize { label in
                label.enabledTypes = [.url, .timestamp]
                label.text = description
                label.contentMode = .scaleAspectFill
                label.font = .systemFont(ofSize: 14)
                label.lineSpacing = 3
                label.preferredMaxLayoutWidth = (detailsSize?.width ?? 330) - 30
                label.URLColor = UIColor(Color.accentColor)
                label.timestampColor = UIColor(Color.accentColor)
                label.handleURLTap(urlTapHandler(_:))
                label.handleTimestampTap(timestampTapHandler(_:))
            }
            updateNumberOfLines()
        }

        func updatePreferredMaxLayoutWidth() {
            label.preferredMaxLayoutWidth = (detailsSize?.width ?? 330) - 30
        }

        func updateNumberOfLines() {
            if expand || collapsedLinesDescription > 0 {
                label.numberOfLines = expand ? 0 : collapsedLinesDescription
                label.isHidden = false
            } else {
                label.isHidden = true
            }
        }

        func urlTapHandler(_ url: URL) {
            var urlToOpen = url

            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "yattee"
                if let yatteeURL = components.url {
                    let parser = URLParser(url: urlToOpen, allowFileURLs: false)
                    let destination = parser.destination
                    if destination == .video,
                       parser.videoID == player.currentVideo?.videoID,
                       let time = parser.time
                    {
                        player.backend.seek(to: Double(time), seekType: .userInteracted)
                        return
                    }
                    if destination != nil {
                        urlToOpen = yatteeURL
                    }
                }
            }

            openURL(urlToOpen)
        }

        func timestampTapHandler(_ timestamp: Timestamp) {
            player.backend.seek(to: timestamp.timeInterval, seekType: .userInteracted)
        }
    }
#endif

struct VideoDescription_Previews: PreviewProvider {
    static var previews: some View {
        VideoDescription(video: .fixture, expand: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
