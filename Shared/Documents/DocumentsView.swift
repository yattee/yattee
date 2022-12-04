import SwiftUI

struct DocumentsView: View {
    @ObservedObject private var model = DocumentsModel.shared

    var body: some View {
        BrowserPlayerControls {
            ScrollView(.vertical, showsIndicators: false) {
                if model.directoryContents.isEmpty {
                    NoDocumentsView()
                } else {
                    ForEach(model.sortedDirectoryContents, id: \.absoluteString) { url in
                        let video = Video.local(model.standardizedURL(url) ?? url)
                        PlayerQueueRow(
                            item: PlayerQueueItem(video)
                        )
                        .contextMenu {
                            VideoContextMenuView(video: video)
                        }
                    }
                    .id(model.refreshID)
                    .transition(.opacity)
                }
                Color.clear.padding(.bottom, 50)
            }
            .onAppear {
                if model.directoryURL.isNil {
                    model.goToTop()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if model.canGoBack {
                        Button {
                            withAnimation {
                                model.goBack()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Label("Go back", systemImage: "chevron.left")
                            }
                        }
                        .transaction { t in t.animation = .none }
                        .disabled(!model.canGoBack)
                    }
                }
            }
            .navigationTitle(model.directoryLabel)
            .padding(.horizontal)
            .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
            .backport
            .refreshable {
                DispatchQueue.main.async {
                    self.refresh()
                }
            }
        }
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
