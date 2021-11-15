import Defaults
import Foundation
import SwiftUI

struct VideoDetails: View {
    enum Page {
        case details, queue, related
    }

    @Binding var sidebarQueue: Bool
    @Binding var fullScreen: Bool

    @State private var subscribed = false
    @State private var confirmationShown = false
    @State private var presentingAddToPlaylist = false
    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    @State private var currentPage = Page.details

    @Environment(\.dismiss) private var dismiss
    @Environment(\.inNavigationView) private var inNavigationView

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Default(.showKeywords) private var showKeywords

    init(
        sidebarQueue: Binding<Bool>? = nil,
        fullScreen: Binding<Bool>? = nil
    ) {
        _sidebarQueue = sidebarQueue ?? .constant(true)
        _fullScreen = fullScreen ?? .constant(false)
    }

    var video: Video? {
        player.currentItem?.video
    }

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                Group {
                    HStack(spacing: 0) {
                        title

                        toggleFullScreenDetailsButton
                    }
                    #if os(macOS)
                    .padding(.top, 10)
                    #endif

                    if !video.isNil {
                        Divider()
                    }

                    subscriptionsSection
                        .onChange(of: video) { video in
                            if let video = video {
                                subscribed = subscriptions.isSubscribing(video.channel.id)
                            }
                        }
                }
                .padding(.horizontal)

                if !sidebarQueue {
                    pagePicker
                        .padding(.horizontal)
                }
            }
            .contentShape(Rectangle())
            .onSwipeGesture(
                up: {
                    withAnimation {
                        fullScreen = true
                    }
                },
                down: {
                    withAnimation {
                        if fullScreen {
                            fullScreen = false
                        } else {
                            self.dismiss()
                        }
                    }
                }
            )

            switch currentPage {
            case .details:
                ScrollView(.vertical) {
                    detailsPage
                }
            case .queue:
                PlayerQueueView(sidebarQueue: $sidebarQueue, fullScreen: $fullScreen)
                    .edgesIgnoringSafeArea(.horizontal)

            case .related:
                RelatedView()
                    .edgesIgnoringSafeArea(.horizontal)
            }
        }
        .padding(.top, inNavigationView && fullScreen ? 10 : 0)
        .onAppear {
            if video.isNil && !sidebarQueue {
                currentPage = .queue
            }

            guard video != nil, accounts.app.supportsSubscriptions else {
                subscribed = false
                return
            }
        }
        .onChange(of: sidebarQueue) { queue in
            if queue {
                if currentPage == .queue {
                    currentPage = .details
                }
            } else if video.isNil {
                currentPage = .queue
            }
        }
        .edgesIgnoringSafeArea(.horizontal)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    var title: some View {
        Group {
            if video != nil {
                Text(video!.title)
                    .onAppear {
                        currentPage = .details
                    }

                    .font(.title2.bold())
            } else {
                Text("Not playing")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    var toggleFullScreenDetailsButton: some View {
        Button {
            withAnimation {
                fullScreen.toggle()
            }
        } label: {
            Label("Resize", systemImage: fullScreen ? "chevron.down" : "chevron.up")
                .labelStyle(.iconOnly)
        }
        .help("Toggle fullscreen details")
        .buttonStyle(.plain)
        .keyboardShortcut("t")
    }

    var subscriptionsSection: some View {
        Group {
            if video != nil {
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        if subscribed {
                            Image(systemName: "star.circle.fill")
                        }
                        VStack(alignment: .leading) {
                            Text(video!.channel.name)
                                .font(.system(size: 13))
                                .bold()
                            if let subscribers = video!.channel.subscriptionsString {
                                Text("\(subscribers) subscribers")
                                    .font(.caption2)
                            }
                        }
                    }
                    .foregroundColor(.secondary)

                    if accounts.app.supportsSubscriptions {
                        Spacer()

                        Section {
                            if subscribed {
                                Button("Unsubscribe") {
                                    confirmationShown = true
                                }
                                #if os(iOS)
                                .tint(.gray)
                                #endif
                                .confirmationDialog("Are you you want to unsubscribe from \(video!.channel.name)?", isPresented: $confirmationShown) {
                                    Button("Unsubscribe") {
                                        subscriptions.unsubscribe(video!.channel.id)

                                        withAnimation {
                                            subscribed.toggle()
                                        }
                                    }
                                }
                            } else {
                                Button("Subscribe") {
                                    subscriptions.subscribe(video!.channel.id)

                                    withAnimation {
                                        subscribed.toggle()
                                    }
                                }
                                .tint(.blue)
                            }
                        }
                        .font(.system(size: 13))
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.roundedRectangle)
                    }
                }
            }
        }
    }

    var pagePicker: some View {
        Picker("Page", selection: $currentPage) {
            if !video.isNil {
                Text("Details").tag(Page.details)
                Text("Related").tag(Page.related)
            }
            Text("Queue").tag(Page.queue)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .onDisappear {
            currentPage = .details
        }
    }

    var publishedDateSection: some View {
        Group {
            if let video = player.currentVideo {
                HStack(spacing: 4) {
                    if let published = video.publishedDate {
                        Text(published)
                    }

                    if let publishedAt = video.publishedAt {
                        if video.publishedDate != nil {
                            Text("•")
                                .foregroundColor(.secondary)
                                .opacity(0.3)
                        }
                        Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.system(size: 12))
                .padding(.bottom, -1)
                .foregroundColor(.secondary)
            }
        }
    }

    var countsSection: some View {
        Group {
            if let video = player.currentVideo {
                HStack {
                    ShareButton(
                        contentItem: contentItem,
                        presentingShareSheet: $presentingShareSheet,
                        shareURL: $shareURL
                    )

                    Spacer()

                    if let views = video.viewsCount {
                        videoDetail(label: "Views", value: views, symbol: "eye.fill")
                    }

                    if let likes = video.likesCount {
                        Divider()

                        videoDetail(label: "Likes", value: likes, symbol: "hand.thumbsup.circle.fill")
                    }

                    if let dislikes = video.dislikesCount {
                        Divider()

                        videoDetail(label: "Dislikes", value: dislikes, symbol: "hand.thumbsdown.circle.fill")
                    }

                    Spacer()

                    if accounts.app.supportsUserPlaylists {
                        Button {
                            presentingAddToPlaylist = true
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                                .labelStyle(.iconOnly)
                                .help("Add to Playlist...")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: 35)
                .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $presentingAddToPlaylist) {
            if let video = video {
                AddToPlaylistView(video: video)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $presentingShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        #endif
    }

    private var contentItem: ContentItem {
        ContentItem(video: player.currentVideo!)
    }

    var detailsPage: some View {
        Group {
            if let video = player.currentItem?.video {
                Group {
                    HStack {
                        publishedDateSection
                        Spacer()
                    }

                    Divider()

                    countsSection
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    if let description = video.description {
                        Text(description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.caption)
                            .padding(.bottom, 4)
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
                                    .background(Color("VideoDetailLikesSymbolColor"))
                                    .mask(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
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
        VideoDetails(sidebarQueue: .constant(true))
            .injectFixtureEnvironmentObjects()
    }
}
