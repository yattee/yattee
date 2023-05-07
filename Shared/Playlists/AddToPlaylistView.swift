import Defaults
import Siesta
import SwiftUI

struct AddToPlaylistView: View {
    let video: Video

    @State private var selectedPlaylistID: Playlist.ID = ""

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    @ObservedObject private var model = PlaylistsModel.shared

    var body: some View {
        Group {
            VStack {
                header
                if model.isEmpty {
                    emptyPlaylistsMessage
                } else {
                    form
                }
                Spacer()
                footer
            }
            .frame(maxWidth: 1000, maxHeight: height)
        }
        .onAppear {
            model.load {
                if let playlist = model.find(id: Defaults[.lastUsedPlaylistID]) ?? model.all.first {
                    selectedPlaylistID = playlist.id
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 270)
        .padding(.vertical)
        #elseif os(tvOS)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(Color.background(scheme: colorScheme))
        #else
        .padding(.vertical)
        #endif
    }

    var height: Double {
        #if os(tvOS)
            600
        #else
            .infinity
        #endif
    }

    private var emptyPlaylistsMessage: some View {
        VStack(spacing: 20) {
            Text("You have no Playlists")
                .font(.title2.bold())
            Text("Open \"Playlists\" tab to create new one")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var header: some View {
        HStack {
            Text("Add to Playlist")
                .font(.title2.bold())

            Spacer()

            #if !os(tvOS)
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
            #endif
        }
        .padding(.horizontal)
    }

    private var form: some View {
        VStack(alignment: formAlignment) {
            VideoBanner(video: video)
                .padding(.vertical, 40)

            VStack(alignment: formAlignment) {
                #if os(tvOS)
                    selectPlaylistButton
                #else
                    HStack {
                        Text("Playlist")
                        Menu {
                            Picker("Playlist", selection: $selectedPlaylistID) {
                                ForEach(model.editable) { playlist in
                                    Text(playlist.title).tag(playlist.id)
                                }
                            }
                        } label: {
                            Text(selectedPlaylist?.title ?? "Select Playlist")
                        }
                        .transaction { t in t.animation = nil }
                        .frame(maxWidth: 500, alignment: .trailing)
                        #if os(macOS)
                            .labelsHidden()
                        #endif
                    }
                #endif
            }
        }
        .padding(.horizontal)
    }

    private var formAlignment: HorizontalAlignment {
        #if os(tvOS)
            .trailing
        #else
            .center
        #endif
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Add to Playlist", action: addToPlaylist)
                .disabled(selectedPlaylist.isNil)
                .padding(.top, 30)
            #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
            #endif
        }
        .padding(.horizontal)
    }

    #if os(tvOS)
        private var selectPlaylistButton: some View {
            Button(selectedPlaylist?.title ?? "Select playlist") {
                guard selectedPlaylist != nil else {
                    return // swiftlint:disable:this implicit_return
                }

                selectedPlaylistID = model.editable.next(after: selectedPlaylist!)!.id
            }
            .contextMenu {
                ForEach(model.editable) { playlist in
                    Button(playlist.title) {
                        selectedPlaylistID = playlist.id
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        }
    #endif

    private func addToPlaylist() {
        guard let id = selectedPlaylist?.id else { return }

        model.addVideo(playlistID: id, videoID: video.videoID)

        presentationMode.wrappedValue.dismiss()
    }

    private var selectedPlaylist: Playlist? {
        model.find(id: selectedPlaylistID) ?? model.all.first
    }
}

struct AddToPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        AddToPlaylistView(video: Video.fixture)
            .onAppear {
                PlaylistsModel.shared.playlists = [.fixture]
            }
    }
}
