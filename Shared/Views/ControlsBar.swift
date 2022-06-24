import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct ControlsBar: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerControlsModel> private var playerControls
    @EnvironmentObject<PlayerModel> private var model
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    var presentingControls = true
    var backgroundEnabled = true
    var borderTop = true
    var borderBottom = true
    var detailsTogglePlayer = true

    var body: some View {
        HStack(spacing: 0) {
            detailsButton

            if presentingControls {
                controls
                    .frame(maxWidth: 120)
            }
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.horizontal)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: barHeight)
        .borderTop(height: borderTop ? 0.4 : 0, color: Color("ControlsBorderColor"))
        .borderBottom(height: borderBottom ? 0.4 : 0, color: Color("ControlsBorderColor"))
        .modifier(ControlBackgroundModifier(enabled: backgroundEnabled, edgesIgnoringSafeArea: .bottom))
        #if os(iOS)
            .background(
                EmptyView().sheet(isPresented: $presentingShareSheet) {
                    if let shareURL = shareURL {
                        ShareSheet(activityItems: [shareURL])
                    }
                }
            )
        #endif
    }

    @ViewBuilder var detailsButton: some View {
        if detailsTogglePlayer {
            Button {
                model.togglePlayer()
            } label: {
                details
                    .contentShape(Rectangle())
            }
        } else {
            details
        }
    }

    var controls: some View {
        HStack(spacing: 4) {
            Group {
                Button {
                    model.closeCurrentItem()
                    model.closePiP()
                } label: {
                    Label("Close Video", systemImage: "xmark")
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }

                if playerControls.isPlaying {
                    Button(action: {
                        model.pause()
                    }) {
                        Label("Pause", systemImage: "pause.fill")
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                } else {
                    Button(action: {
                        model.play()
                    }) {
                        Label("Play", systemImage: "play.fill")
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                }
            }
            .disabled(playerControls.isLoadingVideo || model.currentItem.isNil)

            Button(action: { model.advanceToNextItem() }) {
                Label("Next", systemImage: "forward.fill")
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(model.queue.isEmpty)
        }
        .font(.system(size: 24))
    }

    var barHeight: Double {
        55
    }

    var details: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    authorAvatar

                    if accounts.app.supportsSubscriptions,
                       accounts.signedIn,
                       let video = model.currentVideo,
                       subscriptions.isSubscribing(video.channel.id)
                    {
                        Image(systemName: "star.circle.fill")
                            .background(Color.background)
                            .clipShape(Circle())
                            .foregroundColor(.secondary)
                    }
                }
                .contextMenu {
                    if let video = model.currentVideo {
                        Group {
                            Section {
                                if accounts.app.supportsUserPlaylists && accounts.signedIn {
                                    Section {
                                        Button {
                                            navigation.presentAddToPlaylist(video)
                                        } label: {
                                            Label("Add to Playlist...", systemImage: "text.badge.plus")
                                        }

                                        if let playlist = playlists.lastUsed, let video = model.currentVideo {
                                            Button {
                                                playlists.addVideo(playlistID: playlist.id, videoID: video.videoID, navigation: navigation)
                                            } label: {
                                                Label("Add to \(playlist.title)", systemImage: "text.badge.star")
                                            }
                                        }
                                    }
                                }

                                ShareButton(
                                    contentItem: .init(video: model.currentVideo),
                                    presentingShareSheet: $presentingShareSheet,
                                    shareURL: $shareURL
                                )

                                Section {
                                    Button {
                                        NavigationModel.openChannel(
                                            video.channel,
                                            player: model,
                                            recents: recents,
                                            navigation: navigation
                                        )
                                    } label: {
                                        Label("\(video.author) Channel", systemImage: "rectangle.stack.fill.badge.person.crop")
                                    }

                                    if accounts.app.supportsSubscriptions, accounts.signedIn {
                                        if subscriptions.isSubscribing(video.channel.id) {
                                            Button {
                                                #if os(tvOS)
                                                    subscriptions.unsubscribe(video.channel.id)
                                                #else
                                                    navigation.presentUnsubscribeAlert(video.channel, subscriptions: subscriptions)
                                                #endif
                                            } label: {
                                                Label("Unsubscribe", systemImage: "xmark.circle")
                                            }
                                        } else {
                                            Button {
                                                subscriptions.subscribe(video.channel.id) {
                                                    navigation.sidebarSectionChanged.toggle()
                                                }
                                            } label: {
                                                Label("Subscribe", systemImage: "star.circle")
                                            }
                                        }
                                    }
                                }
                            }

                            Button {
                                model.closeCurrentItem()
                            } label: {
                                Label("Close Video", systemImage: "xmark")
                            }
                        }
                        .labelStyle(.automatic)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.currentVideo?.title ?? "Not playing")
                        .font(.system(size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(model.currentVideo.isNil ? .secondary : .accentColor)
                        .lineLimit(1)

                    Text(model.currentVideo?.author ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical)

            Spacer()
        }
    }

    private var authorAvatar: some View {
        Group {
            if let video = model.currentItem?.video, let url = video.channel.thumbnailURL {
                WebImage(url: url)
                    .resizable()
                    .placeholder {
                        Rectangle().fill(Color("PlaceholderColor"))
                    }
                    .retryOnAppear(true)
                    .indicator(.activity)
            } else {
                ZStack {
                    Color(white: 0.8)
                        .opacity(0.5)

                    Image(systemName: "play.rectangle")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))
                        .contentShape(Rectangle())
                }
            }
        }
        .frame(width: 44, height: 44, alignment: .leading)
        .clipShape(Circle())
    }
}

struct ControlsBar_Previews: PreviewProvider {
    static var previews: some View {
        ControlsBar()
            .injectFixtureEnvironmentObjects()
    }
}
