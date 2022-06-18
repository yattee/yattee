import Defaults
import Siesta
import SwiftUI

struct AddToPlaylistView: View {
    let video: Video

    @State private var selectedPlaylistID: Playlist.ID = ""

    @State private var error = ""
    @State private var presentingErrorAlert = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaylistsModel> private var model

    var body: some View {
        Group {
            VStack {
                if model.isEmpty {
                    emptyPlaylistsMessage
                } else {
                    header
                    Spacer()
                    form
                    Spacer()
                    footer
                }
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
        HStack(alignment: .center) {
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
                    Picker("Playlist", selection: $selectedPlaylistID) {
                        ForEach(model.all) { playlist in
                            Text(playlist.title).tag(playlist.id)
                        }
                    }
                    .frame(maxWidth: 500)
                    #if os(iOS)
                        .pickerStyle(.inline)
                    #elseif os(macOS)
                        .labelsHidden()

                    #endif
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

                selectedPlaylistID = model.all.next(after: selectedPlaylist!)!.id
            }
            .contextMenu {
                ForEach(model.all) { playlist in
                    Button(playlist.title) {
                        selectedPlaylistID = playlist.id
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        }
    #endif

    private func addToPlaylist() {
        guard let id = selectedPlaylist?.id else {
            return
        }

        Defaults[.lastUsedPlaylistID] = id

        model.addVideo(playlistID: id, videoID: video.videoID, navigation: navigation)

        presentationMode.wrappedValue.dismiss()
    }

    private var selectedPlaylist: Playlist? {
        model.find(id: selectedPlaylistID) ?? model.all.first
    }
}

struct AddToPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        AddToPlaylistView(video: Video.fixture)
            .injectFixtureEnvironmentObjects()
    }
}
