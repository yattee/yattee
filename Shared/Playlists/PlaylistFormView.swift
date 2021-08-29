import Siesta
import SwiftUI

struct PlaylistFormView: View {
    @State private var name = ""
    @State private var visibility = Playlist.Visibility.public

    @State private var valid = false
    @State private var showingDeleteConfirmation = false

    @FocusState private var focused: Bool

    @Binding var playlist: Playlist!

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<Playlists> private var playlists

    var editing: Bool {
        playlist != nil
    }

    var body: some View {
        #if os(macOS) || os(iOS)
            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    Text(editing ? "Edit Playlist" : "Create Playlist")
                        .font(.title2.bold())

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }.keyboardShortcut(.cancelAction)
                }
                Form {
                    TextField("Name", text: $name, onCommit: validate)
                        .frame(maxWidth: 450)
                        .padding(.leading, 10)
                        .focused($focused)

                    Picker("Visibility", selection: $visibility) {
                        ForEach(Playlist.Visibility.allCases, id: \.self) { visibility in
                            Text(visibility.name)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Divider()
                    .padding(.vertical, 4)
                HStack {
                    if editing {
                        deletePlaylistButton
                    }

                    Spacer()

                    Button("Save", action: submitForm)
                        .disabled(!valid)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onChange(of: name) { _ in validate() }
            .onAppear(perform: initializeForm)
            .padding(.horizontal)
            #if !os(iOS)
                .frame(width: 400, height: 150)
            #endif

        #else
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
        #endif
    }

    func initializeForm() {
        focused = true

        guard editing else {
            return
        }

        name = playlist.title
        visibility = playlist.visibility

        validate()
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
            if let modifiedPlaylist: Playlist = response.typedContent() {
                playlist = modifiedPlaylist
            }

            playlists.reload()

            dismiss()
        }
    }

    var resource: Resource {
        editing ? InvidiousAPI.shared.playlist(playlist.id) : InvidiousAPI.shared.playlists
    }

    var visibilityButton: some View {
        #if os(macOS)
            Picker("Visibility", selection: $visibility) {
                ForEach(Playlist.Visibility.allCases) { visibility in
                    Text(visibility.name)
                }
            }
        #else
            Button(self.visibility.name) {
                self.visibility = self.visibility.next()
            }
            .contextMenu {
                ForEach(Playlist.Visibility.allCases) { visibility in
                    Button(visibility.name) {
                        self.visibility = visibility
                    }
                }
            }
        #endif
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
        #if os(macOS)
            .foregroundColor(.red)
        #endif
    }

    func deletePlaylistAndDismiss() {
        let resource = InvidiousAPI.shared.playlist(playlist.id)
        resource.request(.delete).onSuccess { _ in
            playlist = nil
            dismiss()
        }
    }
}

struct PlaylistFormView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistFormView(playlist: .constant(Playlist.fixture))
    }
}
