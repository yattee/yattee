import Siesta
import SwiftUI

struct PlaylistFormView: View {
    @State private var name = ""
    @State private var visibility = PlaylistVisibility.public

    @State private var valid = false
    @State private var showingDeleteConfirmation = false

    @Binding var playlist: Playlist!

    @Environment(\.dismiss) private var dismiss

    var editing: Bool {
        playlist != nil
    }

    var body: some View {
        HStack {
            Spacer()

            VStack {
                Spacer()

                CoverSectionView(editing ? "Edit Playlist" : "Create Playlist") {
                    CoverSectionRowView("Name") {
                        TextField("Playlist Name", text: $name, onCommit: validate)
                            .frame(maxWidth: 450)
                    }

                    CoverSectionRowView("Visibility") { visibilityButton }
                }

                CoverSectionRowView {
                    Button("Save", action: submitForm).disabled(!valid)
                }

                if editing {
                    CoverSectionView("Delete Playlist", divider: false, inline: true) { deletePlaylistButton }
                        .padding(.top, 50)
                }

                Spacer()
            }
            .frame(maxWidth: 800)

            Spacer()
        }
        .background(.thinMaterial)
        .onAppear {
            guard editing else {
                return
            }

            self.name = self.playlist.title
            self.visibility = self.playlist.visibility

            validate()
        }
    }

    func validate() {
        valid = !name.isEmpty
    }

    func submitForm() {
        guard valid else {
            return
        }

        let body = ["title": name, "privacy": visibility.rawValue]

        resource.request(editing ? .patch : .post, json: body).onSuccess { response in
            if let createdPlaylist: Playlist = response.typedContent() {
                playlist = createdPlaylist
            }

            dismiss()
        }
    }

    var resource: Resource {
        editing ? InvidiousAPI.shared.playlist(playlist.id) : InvidiousAPI.shared.playlists
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

    var deletePlaylistButton: some View {
        Button("Delete", role: .destructive) {
            showingDeleteConfirmation = true
        }.alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Are you sure you want to delete playlist?"),
                message: Text("Playlist \"\(playlist.title)\" will be deleted.\nIt cannot be undone."),
                primaryButton: .destructive(Text("Delete"), action: deletePlaylistAndDismiss),
                secondaryButton: .cancel()
            )
        }
    }

    func deletePlaylistAndDismiss() {
        let resource = InvidiousAPI.shared.playlist(playlist.id)
        resource.request(.delete).onSuccess { _ in
            playlist = nil
            dismiss()
        }
    }
}
