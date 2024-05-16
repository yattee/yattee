import SwiftUI

struct ShareButton<LabelView: View>: View {
    let contentItem: ContentItem

    @ObservedObject private var accounts = AccountsModel.shared
    private var navigation: NavigationModel { .shared }
    @ObservedObject private var player = PlayerModel.shared

    let label: LabelView?

    init(
        contentItem: ContentItem,
        @ViewBuilder label: @escaping () -> LabelView? = {
            Label("Share...", systemImage: "square.and.arrow.up")
        }
    ) {
        self.contentItem = contentItem
        self.label = label()
    }

    @ViewBuilder var body: some View {
        // TODO: this should work with other content item types
        if let video = contentItem.video {
            Menu {
                if !video.localStreamIsFile {
                    if video.localStreamIsRemoteURL {
                        remoteURLAction
                    } else {
                        instanceActions
                        Divider()
                        if !accounts.isEmpty {
                            youtubeActions
                        }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .help("Share")
            #if os(macOS)
                .frame(maxWidth: 60)
            #endif
        }
    }

    private var instanceActions: some View {
        Group {
            Button(labelForShareURL(accounts.app.name)) {
                if let url = player.playerAPI(contentItem.video)?.shareURL(contentItem) {
                    shareAction(url)
                } else {
                    navigation.presentAlert(
                        title: "Could not create share link",
                        message: "For custom locations you can configure Frontend URL in Locations settings"
                    )
                }
            }

            if contentItemIsPlayerCurrentVideo {
                Button(labelForShareURL(accounts.app.name, withTime: true)) {
                    if let video = player.videoForDisplay,
                       let api = player.playerAPI(video)
                    {
                        shareAction(
                            api.shareURL(
                                contentItem,
                                time: player.backend.currentTime
                            )!
                        )
                    }
                }
            }
        }
    }

    private var youtubeActions: some View {
        Group {
            if let url = accounts.api.shareURL(contentItem, frontendURLString: "https://www.youtube.com") {
                Button(labelForShareURL("YouTube")) {
                    shareAction(url)
                }

                if contentItemIsPlayerCurrentVideo {
                    Button(labelForShareURL("YouTube", withTime: true)) {
                        shareAction(
                            accounts.api.shareURL(
                                contentItem,
                                frontendURLString: "https://www.youtube.com",
                                time: player.backend.currentTime
                            )!
                        )
                    }
                }
            }
        }
    }

    private var contentItemIsPlayerCurrentVideo: Bool {
        contentItem.contentType == .video && contentItem.video?.videoID == player.videoForDisplay?.videoID
    }

    @ViewBuilder private var remoteURLAction: some View {
        if let url = contentItem.video.localStream?.localURL {
            Button(labelForShareURL()) {
                shareAction(url)
            }
        }
    }

    private func shareAction(_ url: URL) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
            player.pause()
            navigation.shareURL = url
            navigation.presentingShareSheet = true
        #endif
    }

    private func labelForShareURL(_ app: String? = nil, withTime: Bool = false) -> String {
        if withTime {
            #if os(macOS)
                return String(format: "Copy %@ link with time".localized(), app ?? "")
            #else
                return String(format: "Share %@ link with time".localized(), app ?? "")
            #endif
        } else {
            #if os(macOS)
                return String(format: "Copy%@link".localized(), app == nil ? " " : " \(app!) ")
            #else
                return String(format: "Share%@link".localized(), app == nil ? " " : " \(app!) ")
            #endif
        }
    }
}

struct ShareButton_Previews: PreviewProvider {
    static var previews: some View {
        ShareButton(
            contentItem: ContentItem(video: Video.fixture)
        )
        .injectFixtureEnvironmentObjects()
    }
}
