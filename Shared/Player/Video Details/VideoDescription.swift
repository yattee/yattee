#if os(iOS)
    import ActiveLabel
#endif
import Defaults
import Foundation
import SwiftUI

struct VideoDescription: View {
    private var search: SearchModel { .shared }
    @Default(.showKeywords) private var showKeywords

    var video: Video
    var detailsSize: CGSize?

    var description: String {
        video.description ?? ""
    }

    var body: some View {
        VStack {
            #if os(iOS)
                ActiveLabelDescriptionRepresentable(description: description, detailsSize: detailsSize)
            #else
                textDescription
            #endif

            keywords
        }
        .id(video.videoID)
    }

    @ViewBuilder var textDescription: some View {
        #if !os(iOS)
            Group {
                if #available(macOS 12, *) {
                    Text(description)
                    #if !os(tvOS)
                        .textSelection(.enabled)
                    #endif
                } else {
                    Text(description)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 14))
            .lineSpacing(3)
        #endif
    }

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
        #if os(macOS)
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

        @State private var label = ActiveLabel()

        @Environment(\.openURL) private var openURL

        var player = PlayerModel.shared

        func makeUIView(context _: Context) -> some UIView {
            customizeLabel()
            return label
        }

        func updateUIView(_: UIViewType, context _: Context) {
            updatePreferredMaxLayoutWidth()
        }

        func customizeLabel() {
            label.customize { label in
                label.enabledTypes = [.url, .timestamp]
                label.numberOfLines = 0
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
        }

        func updatePreferredMaxLayoutWidth() {
            label.preferredMaxLayoutWidth = (detailsSize?.width ?? 330) - 30
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
                    } else if destination != nil {
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
        VideoDescription(video: .fixture)
            .injectFixtureEnvironmentObjects()
    }
}
