import SDWebImageSwiftUI
import SwiftUI

struct ThumbnailView: View {
    var url: URL?
    private let thumbnails = ThumbnailsModel.shared

    var body: some View {
        WebImage(url: url)
            .resizable()
            .onFailure { _ in
                if let url {
                    thumbnails.insertUnloadable(url)
                }
            }
            .placeholder {
                Rectangle().fill(Color("PlaceholderColor"))
            }
    }
}
