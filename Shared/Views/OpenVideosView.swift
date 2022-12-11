import SwiftUI

struct OpenVideosView: View {
    @State private var presentingFileImporter = false
    @State private var urlsToOpenText = ""
    @State private var playbackMode = OpenVideosModel.PlaybackMode.playNow
    @State private var removeQueueItems = false

    @ObservedObject private var navigation = NavigationModel.shared

    @Environment(\.openURL) private var openURL
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        #if os(macOS)
            openVideos
                .frame(minWidth: 600, maxWidth: 800, minHeight: 350, maxHeight: 500)
        #else
            NavigationView {
                ScrollView(.vertical, showsIndicators: false) {
                    openVideos
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        closeButton
                    }
                }
                .navigationTitle("Open Videos")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        #endif
    }

    var closeButton: some View {
        Button(action: { presentationMode.wrappedValue.dismiss() }) {
            Label("Done", systemImage: "xmark")
        }
        #if os(macOS)
        .labelStyle(.titleOnly)
        #endif
        #if !os(tvOS)
        .keyboardShortcut(.cancelAction)
        #endif
    }

    var openVideos: some View {
        VStack(alignment: .leading) {
            #if os(macOS)
                closeButton
            #endif

            ZStack(alignment: .topLeading) {
                #if os(tvOS)
                    TextField("URL to Open", text: $urlsToOpenText)
                #else
                    TextEditor(text: $urlsToOpenText)
                        .padding(2)
                        .border(Color(white: 0.8), width: 1)
                        .frame(minHeight: 100, maxHeight: 250)
                    #if !os(macOS)
                        .keyboardType(.URL)
                    #endif
                #endif
            }

            Group {
                #if os(tvOS)
                    Text("Enter link to open")
                #else
                    Text("Enter links to open, one per line")
                #endif
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            playbackModeControl

            Toggle(isOn: $removeQueueItems) {
                Text("Clear Queue before opening")
            }
            .disabled(!playbackMode.allowsRemovingQueueItems)
            .padding(.bottom)

            HStack {
                Group {
                    #if os(tvOS)
                        Spacer()
                    #endif
                    openURLsButton
                    Spacer()

                    #if !os(tvOS)
                        openFromClipboardButton
                    #endif
                }
            }
            .padding(.bottom, 10)

            #if !os(tvOS)
                openFilesButton
            #endif

            Spacer()
        }
        .padding()
        .alert(isPresented: $navigation.presentingAlertInOpenVideos) { navigation.alert }
        #if !os(tvOS)
            .fileImporter(
                isPresented: $presentingFileImporter,
                allowedContentTypes: [.audiovisualContent],
                allowsMultipleSelection: true
            ) { result in
                do {
                    let selectedFiles = try result.get()
                    let urlsToOpen = selectedFiles.map { url in
                        if let bookmarkURL = URLBookmarkModel.shared.loadBookmark(url) {
                            return bookmarkURL
                        }

                        if url.startAccessingSecurityScopedResource() {
                            URLBookmarkModel.shared.saveBookmark(url)
                        }

                        return url
                    }

                    openURLs(urlsToOpen)
                } catch {
                    navigation.alert = Alert(title: Text("Could not open Files"))
                    navigation.presentingAlertInOpenVideos = true
                }

                presentationMode.wrappedValue.dismiss()
            }
        #endif
    }

    var playbackModeControl: some View {
        HStack {
            #if !os(tvOS)
                Text("Playback Mode")
                Spacer()
            #endif
            #if os(iOS)
                Menu {
                    playbackModePicker
                } label: {
                    Text(playbackMode.description)
                }
            #else
                playbackModePicker
                #if !os(tvOS)
                .frame(maxWidth: 200)
                #endif
            #endif
        }
        .transaction { t in t.animation = .none }
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var playbackModePicker: some View {
        Picker("Playback Mode", selection: $playbackMode) {
            ForEach(OpenVideosModel.PlaybackMode.allCases, id: \.rawValue) { mode in
                Text(mode.description).tag(mode)
            }
        }
        .labelsHidden()
    }

    var openURLsButton: some View {
        OpenVideosButton(text: "Open", imageSystemName: "network") {
            openURLs(urlsToOpenFromText)
        }
        .disabled(urlsToOpenFromText.isEmpty)
        #if os(tvOS)
            .frame(maxWidth: 600)
        #else
            .keyboardShortcut(.defaultAction)
        #endif
    }

    var openFromClipboardButton: some View {
        OpenVideosButton(text: "Paste", imageSystemName: "doc.on.clipboard.fill") {
            OpenVideosModel.shared.openURLsFromClipboard(
                removeQueueItems: removeQueueItems,
                playbackMode: playbackMode
            )
        }
    }

    var openFilesButton: some View {
        OpenVideosButton(text: "Open Files", imageSystemName: "folder") {
            presentingFileImporter = true
        }
    }

    var urlsToOpenFromText: [URL] {
        OpenVideosModel.shared.urlsFrom(urlsToOpenText)
    }

    func openURLs(_ urls: [URL]) {
        OpenVideosModel.shared.openURLs(urls, removeQueueItems: removeQueueItems, playbackMode: playbackMode)

        presentationMode.wrappedValue.dismiss()
    }
}

struct OpenVideosView_Previews: PreviewProvider {
    static var previews: some View {
        OpenVideosView()
            .injectFixtureEnvironmentObjects()
        #if os(iOS)
            .navigationViewStyle(.stack)
        #endif
    }
}
