import SwiftUI

struct OpenVideosView: View {
    @State private var presentingFileImporter = false
    @State private var urlsToOpenText = "https://r.yattee.stream/demo/mp4/1.mp4\nhttps://r.yattee.stream/demo/mp4/2.mp4\nhttps://r.yattee.stream/demo/mp4/3.mp4\nhttps://www.youtube.com/watch?v=N9WHp8DG2WY"
    @State private var playbackMode = OpenVideosModel.PlaybackMode.playNow
    @State private var removeQueueItems = false

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search

    @Environment(\.openURL) private var openURL
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        #if os(macOS)
            openVideos
                .frame(minWidth: 600, maxWidth: 800, minHeight: 250)
        #else
            NavigationView {
                openVideos
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                                Label("Close", systemImage: "xmark")
                            }
                            #if !os(tvOS)
                            .keyboardShortcut(.cancelAction)
                            #endif
                        }
                    }
                    .navigationTitle("Open Videos")
            }
        #endif
    }

    var openVideos: some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .topLeading) {
                #if os(tvOS)
                    TextField("URLs to Open", text: $urlsToOpenText)
                #else
                    TextEditor(text: $urlsToOpenText)
                        .padding(2)
                        .border(Color(white: 0.8), width: 1)
                        .frame(maxHeight: 200)
                    #if !os(macOS)
                        .keyboardType(.URL)
                    #endif
                #endif
            }

            Text("Enter or paste URLs to open, one per line")
                .font(.caption2)
                .foregroundColor(.secondary)

            Picker("Playback Mode", selection: $playbackMode) {
                ForEach(OpenVideosModel.PlaybackMode.allCases, id: \.rawValue) { mode in
                    Text(mode.description).tag(mode)
                }
            }
            .labelsHidden()
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .center)

            Toggle(isOn: $removeQueueItems) {
                Text("Clear queue before opening")
            }
            .disabled(!playbackMode.allowsRemovingQueueItems)
            .padding(.bottom)

            HStack {
                Group {
                    Button {
                        openURLs(urlsToOpenFromText)
                    } label: {
                        HStack {
                            Image(systemName: "network")
                            Text("Open URLs")
                                .fontWeight(.bold)
                                .padding(.vertical, 10)
                        }
                        .padding(.horizontal, 20)
                    }
                    .disabled(urlsToOpenFromText.isEmpty)
                    #if !os(tvOS)
                        .keyboardShortcut(.defaultAction)
                    #endif

                    Spacer()

                    Button {
                        presentingFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("Open Files")
                                .fontWeight(.bold)
                                .padding(.vertical, 10)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .foregroundColor(.accentColor)

                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .foregroundColor(Color.accentColor.opacity(0.33))
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
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

                    openURLs(selectedFiles)
                } catch {
                    NavigationModel.shared.presentAlert(title: "Could not open Files")
                }

                presentationMode.wrappedValue.dismiss()
            }
        #endif
    }

    var urlsToOpenFromText: [URL] {
        urlsToOpenText.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0)) }
    }

    func openURLs(_ urls: [URL]) {
        OpenVideosModel.shared.openURLs(urls, removeQueueItems: removeQueueItems, playbackMode: playbackMode)

        presentationMode.wrappedValue.dismiss()
    }
}

struct OpenVideosView_Previews: PreviewProvider {
    static var previews: some View {
        OpenVideosView()
        #if os(iOS)
            .navigationViewStyle(.stack)
        #endif
    }
}
