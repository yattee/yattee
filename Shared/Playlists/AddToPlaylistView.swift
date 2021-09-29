import Defaults
import Siesta
import SwiftUI

struct AddToPlaylistView: View {
    @EnvironmentObject<PlaylistsModel> private var model

    let video: Video

    @Environment(\.dismiss) private var dismiss

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
                if let playlist = model.all.first {
                    model.selectedPlaylistID = playlist.id
                }
            }
        }
        #if os(macOS)
            .frame(width: 500, height: 270)
            .padding(.vertical)
        #elseif os(tvOS)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(.thickMaterial)
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
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            #endif
        }
        .padding(.horizontal)
    }

    private var form: some View {
        VStack(alignment: formAlignment) {
            VStack(alignment: .leading, spacing: 10) {
                Text(video.title)
                    .font(.headline)
                Text(video.author)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 40)

            VStack(alignment: formAlignment) {
                #if os(tvOS)
                    selectPlaylistButton
                #else
                    Picker("Playlist", selection: $model.selectedPlaylistID) {
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
            #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
            #endif
            .disabled(model.currentPlaylist.isNil)
                .padding(.top, 30)
        }
        .padding(.horizontal)
    }

    private var selectPlaylistButton: some View {
        Button(model.currentPlaylist?.title ?? "Select playlist") {
            guard model.currentPlaylist != nil else {
                return
            }

            model.selectedPlaylistID = model.all.next(after: model.currentPlaylist!)!.id
        }
        .contextMenu {
            ForEach(model.all) { playlist in
                Button(playlist.title) {
                    model.selectedPlaylistID = playlist.id
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    private func addToPlaylist() {
        guard model.currentPlaylist != nil else {
            return
        }

        model.addVideoToCurrentPlaylist(videoID: video.id) {
            dismiss()
        }
    }
}

struct AddToPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        AddToPlaylistView(video: Video.fixture)
            .injectFixtureEnvironmentObjects()
    }
}
