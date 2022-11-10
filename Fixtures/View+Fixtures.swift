import Foundation
import SwiftUI

struct FixtureEnvironmentObjectsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(AccountsModel())
            .environmentObject(comments)
            .environmentObject(InstancesModel())
            .environmentObject(InstancesManifest())
            .environmentObject(invidious)
            .environmentObject(NavigationModel())
            .environmentObject(NetworkStateModel())
            .environmentObject(PipedAPI())
            .environmentObject(player)
            .environmentObject(playerControls)
            .environmentObject(PlayerTimeModel())
            .environmentObject(PlaylistsModel())
            .environmentObject(RecentsModel())
            .environmentObject(SearchModel())
            .environmentObject(SettingsModel())
            .environmentObject(subscriptions)
            .environmentObject(ThumbnailsModel())
    }

    private var comments: CommentsModel {
        let comments = CommentsModel()
        comments.loaded = true
        comments.all = [.fixture]

        return comments
    }

    private var invidious: InvidiousAPI {
        let api = InvidiousAPI()

        api.validInstance = true

        return api
    }

    private var player: PlayerModel {
        let player = PlayerModel()

        player.currentItem = PlayerQueueItem(
            Video(
                videoID: "https://a/b/c",
                title: "Video Name",
                author: "",
                length: 0,
                published: "2 days ago",
                views: 43434,
                description: "The 14\" and 16\" MacBook Pros are incredible. I can finally retire the travel iMac.\nThat shirt! http://shop.MKBHD.com\nMacBook Pro skins: https://dbrand.com/macbooks\n\n0:00 Intro\n1:38 Top Notch Design\n2:27 Let's Talk Ports\n7:11 RIP Touchbar\n8:20 The new displays\n10:12 Living with the notch\n12:37 Performance\n19:39 Battery\n20:30 So should you get it?\n\nThe Verge Review: https://youtu.be/ftU1HzBKd5Y\nTyler Stalman Review: https://youtu.be/I10WMJV96ns\nDeveloper's tweet: https://twitter.com/softwarejameson/status/1455971162060697613?s=09&t=WbOkVKgDdcegIdyOdurSNQ&utm_source=pocket_mylist\n\nTech I'm using right now: https://www.amazon.com/shop/MKBHD\n\nIntro Track: http://youtube.com/20syl\nPlaylist of MKBHD Intro music: https://goo.gl/B3AWV5\n\nLaptop provided by Apple for review.\n\n~\nhttp://twitter.com/MKBHD\nhttp://instagram.com/MKBHD\nhttp://facebook.com/MKBHD",
                channel: .init(id: "", name: "Channel Name"),
                likes: 2332,
                dislikes: 30,
                keywords: ["Video", "Computer", "Long Long Keyword"],
                chapters: [
                    .init(
                        title: "Abc",
                        image: URL(string: "https://pipedproxy.kavin.rocks/vi/rr2XfL_df3o/hqdefault_29633.jpg?sqp=-oaymwEcCNACELwBSFXyq4qpAw4IARUAAIhCGAFwAcABBg%3D%3D&rs=AOn4CLDFDm9D5SvsIA7D3v5n5KZahLs_UA&host=i.ytimg.com")!,
                        start: 3
                    ),
                    .init(
                        title: "Def",
                        image: URL(string: "https://pipedproxy.kavin.rocks/vi/rr2XfL_df3o/hqdefault_98900.jpg?sqp=-oaymwEcCNACELwBSFXyq4qpAw4IARUAAIhCGAFwAcABBg%3D%3D&rs=AOn4CLCfjXJBJb2O2q0jT0RHIi7hARVahw&host=i.ytimg.com")!,
                        start: 33
                    )
                ]
            )
        )
        #if os(iOS)
            player.playerSize = .init(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        #endif
        player.queue = Video.allFixtures.map { PlayerQueueItem($0) }

        return player
    }

    private var playerControls: PlayerControlsModel {
        PlayerControlsModel(presentingControls: true)
    }

    private var subscriptions: SubscriptionsModel {
        let subscriptions = SubscriptionsModel()

        subscriptions.channels = Video.allFixtures.map { $0.channel }

        return subscriptions
    }
}

extension View {
    func injectFixtureEnvironmentObjects() -> some View {
        modifier(FixtureEnvironmentObjectsModifier())
    }
}
