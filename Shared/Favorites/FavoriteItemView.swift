import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

final class FavoriteResourceObserver: ObservableObject, ResourceObserver {
    @Published var videos = [Video]()

    func resourceChanged(_ resource: Resource, event _: ResourceEvent) {
        if let videos: [Video] = resource.typedContent() {
            self.videos = videos
        } else if let channel: Channel = resource.typedContent() {
            videos = channel.videos
        } else if let playlist: ChannelPlaylist = resource.typedContent() {
            videos = playlist.videos
        } else if let playlist: Playlist = resource.typedContent() {
            videos = playlist.videos
        }
    }
}

struct FavoriteItemView: View {
    let item: FavoriteItem
    let resource: Resource?

    @StateObject private var store = FavoriteResourceObserver()

    @Binding private var favorites: [FavoriteItem]
    @Binding private var dragging: FavoriteItem?

    @EnvironmentObject<PlaylistsModel> private var playlistsModel

    init(
        item: FavoriteItem,
        resource: Resource?,
        favorites: Binding<[FavoriteItem]>,
        dragging: Binding<FavoriteItem?>
    ) {
        self.item = item
        self.resource = resource
        _favorites = favorites
        _dragging = dragging
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.title3.bold())
                .foregroundColor(.secondary)

                .contextMenu {
                    Button {
                        FavoritesModel.shared.remove(item)
                    } label: {
                        Label("Remove from Favorites", systemImage: "trash")
                    }
                }
                .contentShape(Rectangle())
            #if os(tvOS)
                .padding(.leading, 40)
            #else
                .padding(.leading, 15)
            #endif

            HorizontalCells(items: store.videos.map { ContentItem(video: $0) })
        }

        .contentShape(Rectangle())
        .opacity(dragging?.id == item.id ? 0.5 : 1)
        .onAppear {
            resource?.addObserver(store)
            resource?.loadIfNeeded()
        }
        #if !os(tvOS)
            .onDrag {
                dragging = item
                return NSItemProvider(object: item.id as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: DropFavorite(item: item, favorites: $favorites, current: $dragging)
            )
        #endif
    }

    var label: String {
        if case let .playlist(id) = item.section {
            return playlistsModel.find(id: id)?.title ?? "Playlist"
        }

        return item.section.label
    }
}
