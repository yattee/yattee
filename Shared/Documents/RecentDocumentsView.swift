import Defaults
import SwiftUI

struct RecentDocumentsView: View {
    var limit = 3
    let model = DocumentsModel.shared

    var body: some View {
        LazyVStack {
            if recentDocuments.isEmpty {
                NoDocumentsView()
            } else {
                ForEach(recentDocuments, id: \.absoluteString) { url in
                    let video = Video.local(model.replacePrivateVar(url) ?? url)
                    PlayerQueueRow(
                        item: PlayerQueueItem(video)
                    )
                    .contextMenu {
                        VideoContextMenuView(video: video)
                    }
                }
            }
        }
        .padding(.horizontal, 15)
    }

    var recentDocuments: [URL] {
        model.recentDocuments(limit)
    }
}

struct RecentDocumentsView_Previews: PreviewProvider {
    static var previews: some View {
        RecentDocumentsView()
    }
}
