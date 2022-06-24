import Defaults
import SDWebImageSwiftUI
import SwiftUI
import SwiftUIPager

struct ControlsBar: View {
    enum Pages: CaseIterable {
        case details, controls
    }

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerControlsModel> private var playerControls
    @EnvironmentObject<PlayerModel> private var model
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents

    @StateObject private var controlsPage = Page.first()

    var body: some View {
        VStack(spacing: 0) {
            Pager(page: controlsPage, data: Pages.allCases, id: \.self) { index in
                switch index {
                case .details:
                    details
                default:
                    controls
                }
            }
            .pagingPriority(.simultaneous)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.horizontal)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: barHeight)
        .borderTop(height: 0.4, color: Color("ControlsBorderColor"))
        .borderBottom(height: 0.4, color: Color("ControlsBorderColor"))
        .modifier(ControlBackgroundModifier(edgesIgnoringSafeArea: .bottom))
    }

    var controls: some View {
        HStack(spacing: 4) {
            Group {
                Button {
                    model.closeCurrentItem()
                    model.closePiP()
                } label: {
                    Label("Close Video", systemImage: "xmark")
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }

                Spacer()

                Button(action: { model.backend.seek(to: 0) }) {
                    Label("Restart", systemImage: "backward.end.fill")
                        .contentShape(Rectangle())
                }

                Spacer()

                Button {
                    model.backend.seek(relative: .secondsInDefaultTimescale(-10))
                } label: {
                    Label("Backward", systemImage: "gobackward.10")
                }
                Spacer()

                if playerControls.isPlaying {
                    Button(action: {
                        model.pause()
                    }) {
                        Label("Pause", systemImage: "pause.fill")
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                } else {
                    Button(action: {
                        model.play()
                    }) {
                        Label("Play", systemImage: "play.fill")
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                }
                Spacer()

                Button {
                    model.backend.seek(relative: .secondsInDefaultTimescale(10))
                } label: {
                    Label("Forward", systemImage: "goforward.10")
                }

                Spacer()
            }
            .disabled(playerControls.isLoadingVideo || model.currentItem.isNil)

            Button(action: { model.advanceToNextItem() }) {
                Label("Next", systemImage: "forward.fill")
                    .contentShape(Rectangle())
            }
            .disabled(model.queue.isEmpty)

            Spacer()
        }
        .padding(.vertical)

        .font(.system(size: 24))
        .frame(maxWidth: .infinity)
    }

    var barHeight: Double {
        75
    }

    var details: some View {
        HStack {
            HStack(spacing: 8) {
                authorAvatar
                    .contextMenu {
                        if let video = model.currentVideo {
                            Group {
                                Section {
                                    Text(video.title)

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

                                            Button {} label: {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                    }

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

                                        Button {} label: {
                                            Label("Unsubscribe", systemImage: "xmark.circle")
                                        }
                                    }
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
        Button {
            model.togglePlayer()
        } label: {
            if let video = model.currentItem?.video, let url = video.channel.thumbnailURL {
                WebImage(url: url)
                    .resizable()
                    .placeholder {
                        Rectangle().fill(Color("PlaceholderColor"))
                    }
                    .retryOnAppear(true)
                    .indicator(.activity)
            } else {
                Image(systemName: "play.rectangle")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 30))
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
