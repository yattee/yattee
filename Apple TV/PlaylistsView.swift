import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var state: AppState

    @Binding var tabSelection: TabSelection

    @ObservedObject private var provider = PlaylistsProvider()

    @State private var selectedPlaylist: Playlist?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Spacer()

                    selectPlaylistButton

                    Spacer()
                }
                .padding(.bottom, 5)

                VStack {
                    if selectedPlaylist != nil {
                        VideosView(tabSelection: $tabSelection, videos: selectedPlaylist!.videos)
                    }
                }
            }
        }.task {
            Task {
                provider.load { playlists in
                    selectedPlaylist = playlists.first
                }
            }
        }
    }

    var playlists: [Playlist] {
        if provider.playlists.isEmpty {
            provider.load()
        }

        return provider.playlists
    }

    var selectPlaylistButton: some View {
        Button(selectedPlaylist?.title ?? "Select playlist") {
            guard selectedPlaylist != nil else {
                return
            }

            selectedPlaylist = playlists.next(after: selectedPlaylist!)
        }
        .contextMenu {
            ForEach(provider.playlists) { playlist in
                Button(playlist.title) {
                    selectedPlaylist = playlist
                }
            }
        }
    }
}

extension Array where Element: Equatable {
    func next(after element: Element) -> Element? {
        let idx = firstIndex(of: element)!
        let next = index(after: idx)

        return self[next == endIndex ? startIndex : next]
    }
}
