import SwiftUI

struct DocumentsView: View {
    var directoryURL: URL?

    @ObservedObject private var model = DocumentsModel.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let url, model.directoryContents(url).isEmpty {
                NoDocumentsView()
            } else if let url {
                ForEach(model.sortedDirectoryContents(url), id: \.absoluteString) { url in
                    let standardizedURL = model.standardizedURL(url) ?? url
                    let video = Video.local(standardizedURL)

                    Group {
                        if model.isDirectory(standardizedURL) {
                            NavigationLink(destination: Self(directoryURL: url)) {
                                VideoBanner(video: video)
                            }
                        } else {
                            PlayerQueueRow(item: PlayerQueueItem(video))
                        }
                    }
                    .contextMenu {
                        VideoContextMenuView(video: video)
                    }
                }
                .id(model.refreshID)
                .transition(.opacity)
            }
            Color.clear.padding(.bottom, 50)
        }
        .navigationTitle(directoryLabel)
        .padding(.horizontal)
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        .backport
        .refreshable {
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    var url: URL? {
        directoryURL ?? model.documentsDirectory
    }

    var directoryLabel: String {
        guard let directoryURL else { return "Documents" }
        return model.displayLabelForDocument(directoryURL)
    }

    func refresh() {
        withAnimation {
            model.refresh()
        }
    }
}

struct DocumentsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DocumentsView()
        }
        .injectFixtureEnvironmentObjects()
        .navigationViewStyle(.stack)
    }
}
