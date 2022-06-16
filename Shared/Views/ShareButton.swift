import SwiftUI

struct ShareButton: View {
    let contentItem: ContentItem
    @Binding var presentingShareSheet: Bool
    @Binding var shareURL: URL?

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player

    init(
        contentItem: ContentItem,
        presentingShareSheet: Binding<Bool>,
        shareURL: Binding<URL?>? = nil
    ) {
        self.contentItem = contentItem
        _presentingShareSheet = presentingShareSheet
        _shareURL = shareURL ?? .constant(nil)
    }

    var body: some View {
        Menu {
            instanceActions
            Divider()
            youtubeActions
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        #if os(macOS)
            .frame(maxWidth: 35)
        #endif
    }

    private var instanceActions: some View {
        Group {
            if let url = accounts.api.shareURL(contentItem) {
                Button(labelForShareURL(accounts.app.name)) {
                    shareAction(url)
                }

                if contentItem.contentType == .video {
                    Button(labelForShareURL(accounts.app.name, withTime: true)) {
                        shareAction(
                            accounts.api.shareURL(
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
            if let url = accounts.api.shareURL(contentItem, frontendHost: "www.youtube.com") {
                Button(labelForShareURL("YouTube")) {
                    shareAction(url)
                }

                if contentItem.contentType == .video {
                    Button(labelForShareURL("YouTube", withTime: true)) {
                        shareAction(
                            accounts.api.shareURL(
                                contentItem,
                                frontendHost: "www.youtube.com",
                                time: player.backend.currentTime
                            )!
                        )
                    }
                }
            }
        }
    }

    private func shareAction(_ url: URL) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
            player.pause()
            shareURL = url
            presentingShareSheet = true
        #endif
    }

    private func labelForShareURL(_ app: String, withTime: Bool = false) -> String {
        let time = withTime ? "with time" : ""

        #if os(macOS)
            return "Copy \(app) link \(time)"
        #else
            return "Share \(app) link \(time)"
        #endif
    }
}

struct ShareButton_Previews: PreviewProvider {
    static var previews: some View {
        ShareButton(
            contentItem: ContentItem(video: Video.fixture),
            presentingShareSheet: .constant(false)
        )
        .injectFixtureEnvironmentObjects()
    }
}
