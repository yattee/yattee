import Siesta
import SwiftUI

struct PlaylistFormView: View {
    @Binding var playlist: Playlist!

    @State private var name = ""
    @State private var visibility = Playlist.Visibility.public

    @State private var valid = false
    @State private var showingDeleteConfirmation = false

    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<PlaylistsModel> private var playlists

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
                .padding(.horizontal)

                Form {
                    TextField("Name", text: $name, onCommit: validate)
                        .frame(maxWidth: 450)
                        .padding(.leading, 10)
                        .focused($focused)

                    visibilityFormItem
                        .pickerStyle(.segmented)
                }

                HStack {
                    if editing {
                        deletePlaylistButton
                    }

                    Spacer()

                    Button("Save", action: submitForm)
                        .disabled(!valid)
                        .keyboardShortcut(.defaultAction)
                }
                .frame(minHeight: 35)
                .padding(.horizontal)
            }
            .onChange(of: name) { _ in validate() }
            .onAppear(perform: initializeForm)
            #if os(iOS)
                .padding(.vertical)
            #else
                .frame(width: 400, height: 150)
            #endif

        #else
            VStack {
                Group {
                    header
                    form
                }
                .frame(maxWidth: 1000)
            }
            .onAppear {
                guard editing else {
                    return
                }

                self.name = self.playlist.title
                self.visibility = self.playlist.visibility

                validate()
            }

            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(.thickMaterial)
        #endif
    }

    var header: some View {
        HStack(alignment: .center) {
            Text(editing ? "Edit Playlist" : "Create Playlist")
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

    var form: some View {
        VStack(alignment: .trailing) {
            VStack {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("Playlist Name", text: $name, onCommit: validate)
            }

            HStack {
                Text("Visibility")
                    .frame(maxWidth: .infinity, alignment: .leading)

                visibilityFormItem
            }
            .padding(.top, 10)

            HStack {
                Spacer()

                Button("Save", action: submitForm).disabled(!valid)
            }
            .padding(.top, 40)

            if editing {
                Divider()
                HStack {
                    Text("Delete playlist")
                        .font(.title2.bold())
                    Spacer()
                    deletePlaylistButton
                }
            }
        }
        .padding(.horizontal)
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

        resource?.request(editing ? .patch : .post, json: body).onSuccess { response in
            if let modifiedPlaylist: Playlist = response.typedContent() {
                playlist = modifiedPlaylist
            }

            playlists.load(force: true)

            dismiss()
        }
    }

    var resource: Resource? {
        editing ? api.playlist(playlist.id) : api.playlists
    }

    var visibilityFormItem: some View {
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

                #if os(tvOS)
                    Button("Cancel", role: .cancel) {}
                #endif
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
        api.playlist(playlist.id)?.request(.delete).onSuccess { _ in
            playlist = nil
            playlists.load(force: true)
            dismiss()
        }
    }
}

struct PlaylistFormView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistFormView(playlist: .constant(Playlist.fixture))
    }
}
