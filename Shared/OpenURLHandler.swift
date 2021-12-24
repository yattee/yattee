import Foundation

struct OpenURLHandler {
    var accounts: AccountsModel
    var player: PlayerModel

    func handle(_ url: URL) {
        if accounts.current.isNil {
            accounts.setCurrent(accounts.any)
        }

        guard !accounts.current.isNil else {
            return
        }

        #if os(macOS)
            guard url.host != OpenWindow.player.location else {
                return
            }
        #endif

        let parser = VideoURLParser(url: url)

        guard let id = parser.id,
              id != player.currentVideo?.id
        else {
            return
        }

        #if os(macOS)
            OpenWindow.main.open()
        #endif

        accounts.api.video(id).load().onSuccess { response in
            if let video: Video = response.typedContent() {
                self.player.playNow(video, at: parser.time)
                self.player.show()
            }
        }
    }
}
