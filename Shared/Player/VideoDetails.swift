import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI
import SwiftUIPager

struct VideoDetails: View {
    enum DetailsPage: CaseIterable {
        case info, chapters, comments, related, queue

        var index: Int {
            switch self {
            case .info:
                return 0
            case .chapters:
                return 1
            case .comments:
                return 2
            case .related:
                return 3
            case .queue:
                return 4
            }
        }
    }

    var sidebarQueue: Bool
    var fullScreen: Bool

    @State private var subscribed = false
    @State private var subscriptionToggleButtonDisabled = false

    @StateObject private var page: Page = .first()

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Default(.showKeywords) private var showKeywords
    @Default(.playerDetailsPageButtonLabelStyle) private var playerDetailsPageButtonLabelStyle
    @Default(.controlsBarInPlayer) private var controlsBarInPlayer

    var currentPage: DetailsPage {
        DetailsPage.allCases.first { $0.index == page.index } ?? .info
    }

    var video: Video? {
        player.currentVideo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlsBar(
                presentingControls: false,
                backgroundEnabled: false,
                borderTop: false,
                detailsTogglePlayer: false
            )

            HStack(spacing: 4) {
                pageButton("Info", "info.circle", .info, !video.isNil)
                pageButton("Chapters", "bookmark", .chapters, !(video?.chapters.isEmpty ?? true))
                pageButton("Comments", "text.bubble", .comments, !video.isNil) { comments.load() }
                pageButton("Related", "rectangle.stack.fill", .related, !video.isNil)
                pageButton("Queue", "list.number", .queue, !video.isNil)
            }
            .onChange(of: player.currentItem) { _ in
                page.update(.moveToFirst)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Pager(page: page, data: DetailsPage.allCases, id: \.self) {
                detailsByPage($0)
            }
            .onPageWillChange { pageIndex in
                if pageIndex == DetailsPage.comments.index {
                    comments.load()
                }
            }
        }
        .onAppear {
            if video.isNil && !sidebarQueue {
                page.update(.new(index: DetailsPage.queue.index))
            }

            guard video != nil, accounts.app.supportsSubscriptions else {
                subscribed = false
                return
            }
        }
        .onChange(of: sidebarQueue) { queue in
            if queue {
                if currentPage == .related || currentPage == .queue {
                    page.update(.moveToFirst)
                }
            } else if video.isNil {
                page.update(.moveToLast)
            }
        }
        .edgesIgnoringSafeArea(.horizontal)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    var publishedDateSection: some View {
        Group {
            if let video = player.currentVideo {
                HStack(spacing: 4) {
                    if let published = video.publishedDate {
                        Text(published)
                    }
                }
            }
        }
    }

    private var contentItem: ContentItem {
        ContentItem(video: player.currentVideo!)
    }

    func pageButton(
        _ label: String,
        _ symbolName: String,
        _ destination: DetailsPage,
        _ active: Bool = true,
        pageChangeAction: (() -> Void)? = nil
    ) -> some View {
        Button(action: {
            page.update(.new(index: destination.index))
            pageChangeAction?()
        }) {
            HStack {
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: symbolName)

                    if playerDetailsPageButtonLabelStyle.text && player.playerSize.width > 450 {
                        Text(label)
                    }
                }
                .frame(minHeight: 15)
                .lineLimit(1)
                .padding(.vertical, 4)
                .foregroundColor(currentPage == destination ? .white : (active ? Color.accentColor : .gray))

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .background(currentPage == destination ? (active ? Color.accentColor : .gray) : .clear)
        .buttonStyle(.plain)
        .font(.system(size: 10).bold())
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(active ? Color.accentColor : .gray, lineWidth: 2)
                .foregroundColor(.clear)
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder func detailsByPage(_ page: DetailsPage) -> some View {
        Group {
            switch page {
            case .info:
                ScrollView(.vertical, showsIndicators: false) {
                    detailsPage
                }
            case .chapters:
                ChaptersView()
                    .edgesIgnoringSafeArea(.horizontal)

            case .queue:
                PlayerQueueView(sidebarQueue: sidebarQueue, fullScreen: fullScreen)
                    .edgesIgnoringSafeArea(.horizontal)

            case .related:
                RelatedView()
                    .edgesIgnoringSafeArea(.horizontal)
            case .comments:
                CommentsView(embedInScrollView: true)
                    .edgesIgnoringSafeArea(.horizontal)
            }
        }
        .contentShape(Rectangle())
    }

    var detailsPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                if let video = player.currentVideo {
                    VStack(spacing: 6) {
                        videoProperties

                        Divider()
                    }
                    .padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 10) {
                        if !player.videoBeingOpened.isNil && (video.description.isNil || video.description!.isEmpty) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(1 ... Int.random(in: 3 ... 5), id: \.self) { _ in
                                    Text(String(repeating: Video.fixture.description!, count: Int.random(in: 1 ... 4)))
                                        .redacted(reason: .placeholder)
                                }
                            }
                        } else if let description = video.description {
                            Group {
                                if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
                                    Text(description)
                                        .textSelection(.enabled)
                                } else {
                                    Text(description)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                        } else {
                            Text("No description")
                                .foregroundColor(.secondary)
                        }

                        if showKeywords {
                            ScrollView(.horizontal, showsIndicators: showScrollIndicators) {
                                HStack {
                                    ForEach(video.keywords, id: \.self) { keyword in
                                        HStack(alignment: .center, spacing: 0) {
                                            Text("#")
                                                .font(.system(size: 11).bold())

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
                                }
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }

                if !video.isNil, CommentsModel.placement == .info {
                    Divider()
                    #if os(macOS)
                        .padding(.bottom, 20)
                    #else
                        .padding(.vertical, 10)
                    #endif
                }
            }
            .padding(.horizontal)

            LazyVStack {
                if !video.isNil, CommentsModel.placement == .info {
                    CommentsView()
                }
            }
        }
    }

    var videoProperties: some View {
        HStack(spacing: 2) {
            publishedDateSection
            Spacer()

            HStack(spacing: 4) {
                if let views = video?.viewsCount {
                    Image(systemName: "eye")

                    Text(views)
                }

                if let likes = video?.likesCount {
                    Image(systemName: "hand.thumbsup")

                    Text(likes)
                }

                if let likes = video?.dislikesCount {
                    Image(systemName: "hand.thumbsdown")

                    Text(likes)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }

    func videoDetail(label: String, value: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: symbol)

                Text(label.uppercased())
            }
            .font(.system(size: 9))
            .opacity(0.6)

            Text(value)
        }

        .frame(maxWidth: 100)
    }

    var showScrollIndicators: Bool {
        #if os(macOS)
            false
        #else
            true
        #endif
    }
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(sidebarQueue: true, fullScreen: false)
            .injectFixtureEnvironmentObjects()
    }
}
