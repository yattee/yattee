import SwiftUI
import SwiftyJSON

struct NewPlaylistView: View {
    @State private var name = ""
    @State private var visibility = PlaylistVisibility.public

    @State private var valid = false

    @Binding var createdPlaylist: Playlist?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()

            VStack {
                Spacer()

                CoverSectionView("New Playlist") {
                    CoverSectionRowView("Name") {
                        TextField("Playlist Name", text: $name, onCommit: validate)
                            .frame(maxWidth: 450)
                    }

                    CoverSectionRowView("Visibility") { visibilityButton }
                }

                CoverSectionRowView {
                    Button("Create", action: createPlaylistAndDismiss).disabled(!valid)
                }

                Spacer()
            }
            .frame(maxWidth: 800)

            Spacer()
        }
        .background(.thinMaterial)
        .onAppear {
            createdPlaylist = nil
        }
    }

    func validate() {
        valid = !name.isEmpty
    }

    func createPlaylistAndDismiss() {
        let resource = InvidiousAPI.shared.playlists
        let body = ["title": name, "privacy": visibility.rawValue]

        resource.request(.post, json: body).onSuccess { response in
            if let playlist: Playlist = response.typedContent() {
                createdPlaylist = playlist
                dismiss()
            }
        }
    }

    var visibilityButton: some View {
        Button(self.visibility.name) {
            self.visibility = self.visibility.next()
        }
        .contextMenu {
            ForEach(PlaylistVisibility.allCases) { visibility in
                Button(visibility.name) {
                    self.visibility = visibility
                }
            }
        }
    }
}
