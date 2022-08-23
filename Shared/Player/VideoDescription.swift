#if os(iOS)
    import ActiveLabel
#endif
import Defaults
import Foundation
import SwiftUI

struct VideoDescription: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search
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
                            NavigationModel.openSearchQuery(keyword, player: player, recents: recents, navigation: navigation, search: search)
                        } label: {
                            HStack(alignment: .center, spacing: 0) {
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
        @EnvironmentObject<PlayerModel> private var player

        func makeUIView(context _: Context) -> some UIView {
            customizeLabel()
            return label
        }

        func updateUIView(_: UIViewType, context _: Context) {
            customizeLabel()
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
                label.handleURLTap { url in
                    var urlToOpen = url

                    if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        components.scheme = "yattee"
                        if let yatteeURL = components.url {
                            let parser = URLParser(url: urlToOpen)
                            if parser.destination == .video,
                               parser.videoID == player.currentVideo?.videoID,
                               let time = parser.time
                            {
                                player.backend.seek(to: Double(time))
                                return
                            } else {
                                urlToOpen = yatteeURL
                            }
                        }
                    }

                    openURL(urlToOpen)
                }
                label.handleTimestampTap { timestamp in
                    player.backend.seek(to: timestamp.timeInterval)
                }
            }
        }
    }
#endif

struct VideoDescription_Previews: PreviewProvider {
    static var previews: some View {
        VideoDescription(video: .fixture)
            .injectFixtureEnvironmentObjects()
    }
}
