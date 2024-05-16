import Siesta
import SwiftUI

struct PlaylistFormView: View {
    @Binding var playlist: Playlist!

    @State private var name = ""
    @State private var visibility = Playlist.Visibility.public

    @State private var valid = false
    @State private var presentingDeleteConfirmation = false

    @State private var formError = ""
    @State private var presentingErrorAlert = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var playlists = PlaylistsModel.shared

    var editing: Bool {
        playlist != nil
    }

    var body: some View {
        Group {
            #if os(macOS) || os(iOS)
                VStack(alignment: .leading) {
                    HStack {
                        Text(editing ? "Edit Playlist" : "Create Playlist")
                            .font(.title2.bold())

                        Spacer()

                        Button("Cancel") {
                            presentationMode.wrappedValue.dismiss()
                        }.keyboardShortcut(.cancelAction)
                    }
                    .padding(.horizontal)

                    Form {
                        TextField("Name", text: $name, onCommit: validate)
                            .frame(maxWidth: 450)
                            .padding(.leading, 10)
                            .disabled(editing && !accounts.app.userPlaylistsAreEditable)

                        if accounts.app.userPlaylistsHaveVisibility {
                            visibilityFormItem
                                .pickerStyle(.segmented)
                        }
                    }
                    #if os(macOS)
                    .padding(.horizontal)
                    #endif

                    HStack {
                        if editing {
                            deletePlaylistButton
                        }

                        Spacer()

                        Button("Save", action: submitForm)
                            .disabled(!valid || (editing && !accounts.app.userPlaylistsAreEditable))
                            .alert(isPresented: $presentingErrorAlert) {
                                Alert(
                                    title: Text("Error when accessing playlist"),
                                    message: Text(formError)
                                )
                            }
                            .keyboardShortcut(.defaultAction)
                    }
                    .frame(minHeight: 35)
                    .padding(.horizontal)
                }

                #if os(iOS)
                .padding(.vertical)
                #else
                .frame(width: 400, height: accounts.app.userPlaylistsHaveVisibility ? 150 : 120)
                #endif

            #else
                VStack {
                    Group {
                        header
                        form
                    }
                    .frame(maxWidth: 1000)
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(Color.background(scheme: colorScheme))
            #endif
        }
        .onChange(of: name) { _ in validate() }
        .onAppear(perform: initializeForm)
    }

    #if os(tvOS)
        var header: some View {
            HStack {
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
                        .disabled(editing && !accounts.app.userPlaylistsAreEditable)
                }

                if accounts.app.userPlaylistsHaveVisibility {
                    HStack {
                        Text("Visibility")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        visibilityFormItem
                    }
                    .padding(.top, 10)
                }

                HStack {
                    Spacer()

                    Button("Save", action: submitForm)
                        .disabled(!valid || (editing && !accounts.app.userPlaylistsAreEditable))
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
    #endif

    func initializeForm() {
        guard editing else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            name = playlist.title
            visibility = playlist.visibility

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

        accounts.api.playlistForm(name, visibility.rawValue, playlist: playlist, onFailure: { error in
            formError = "(\(error.httpStatusCode ?? -1)) \(error.userMessage)"
            presentingErrorAlert = true
        }) { modifiedPlaylist in
            self.playlist = modifiedPlaylist
            playlists.load(force: true)

            presentationMode.wrappedValue.dismiss()
        }
    }

    var visibilityFormItem: some View {
        #if os(macOS)
            Picker("Visibility", selection: $visibility) {
                ForEach(Playlist.Visibility.allCases) { visibility in
                    Text(visibility.name).tag(visibility)
                }
            }
        #else
            Button(visibility.name) {
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
        Button("Delete") {
            presentingDeleteConfirmation = true
        }
        .alert(isPresented: $presentingDeleteConfirmation) {
            Alert(
                title: Text("Are you sure you want to delete playlist?"),
                message: Text("Playlist \"\(playlist.title)\" will be deleted.\nIt cannot be reverted."),
                primaryButton: .destructive(Text("Delete"), action: deletePlaylistAndDismiss),
                secondaryButton: .cancel()
            )
        }
        .foregroundColor(.red)
    }

    func deletePlaylistAndDismiss() {
        accounts.api.deletePlaylist(playlist, onFailure: { error in
            formError = "(\(error.httpStatusCode ?? -1)) \(error.localizedDescription)"
            presentingErrorAlert = true
        }) {
            playlist = nil
            playlists.load(force: true)
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct PlaylistFormView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistFormView(playlist: .constant(Playlist.fixture))
    }
}
