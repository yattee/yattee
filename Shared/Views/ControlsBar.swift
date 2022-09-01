import CachedAsyncImage
import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct ControlsBar: View {
    @Binding var fullScreen: Bool

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var model
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    var presentingControls = true
    var backgroundEnabled = true
    var borderTop = true
    var borderBottom = true
    var detailsTogglePlayer = true
    var detailsToggleFullScreen = false
    var titleLineLimit = 2

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
        } else if detailsToggleFullScreen {
            Button {
                model.controls.presentingControlsOverlay = false
                model.controls.presentingControls = false
                withAnimation {
                    fullScreen.toggle()
                }
            } label: {
                details
                    .contentShape(Rectangle())
            }
            #if !os(tvOS)
            .keyboardShortcut("t")
            #endif
        } else {
            details
        }
    }

    var controls: some View {
        HStack(spacing: 4) {
            Group {
                if model.controls.isPlaying {
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
            .disabled(model.controls.isLoadingVideo || model.currentItem.isNil)

            Button(action: { model.advanceToNextItem() }) {
                Label("Next", systemImage: "forward.fill")
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(!model.isAdvanceToNextItemAvailable)

            Button {
                model.closeCurrentItem()
            } label: {
                Label("Close Video", systemImage: "xmark")
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(model.currentItem.isNil)
        }
        .imageScale(.small)
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
                        #if !os(tvOS)
                            .background(Color.background)
                        #endif
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

                                #if !os(tvOS)
                                    ShareButton(contentItem: .init(video: model.currentVideo))
                                #endif

                                Section {
                                    Button {
                                        NavigationModel.openChannel(
                                            video.channel,
                                            player: model,
                                            recents: recents,
                                            navigation: navigation,
                                            navigationStyle: navigationStyle
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

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.currentVideo?.title ?? "Not Playing")
                        .font(.system(size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(model.currentVideo.isNil ? .secondary : .accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(titleLineLimit)
                        .multilineTextAlignment(.leading)

                    if let video = model.currentVideo {
                        HStack(spacing: 2) {
                            Text(video.author)
                                .font(.system(size: 12))

                            if !presentingControls {
                                HStack(spacing: 2) {
                                    Image(systemName: "person.2.fill")

                                    if let channel = model.currentVideo?.channel {
                                        if let subscriptions = channel.subscriptionsString {
                                            Text(subscriptions)
                                        } else {
                                            Text("1234").redacted(reason: .placeholder)
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                                .font(.system(size: 9))
                            }
                        }
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                    }
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
                if #available(iOS 15, macOS 12, *) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                    } placeholder: {
                        Rectangle().foregroundColor(Color("PlaceholderColor"))
                    }
                } else {
                    WebImage(url: url)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(Color("PlaceholderColor"))
                        }
                        .retryOnAppear(true)
                        .indicator(.activity)
                }
            } else {
                ZStack {
                    Color(white: 0.6)
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
        ControlsBar(fullScreen: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
