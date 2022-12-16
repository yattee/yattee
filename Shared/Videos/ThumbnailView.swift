import CachedAsyncImage
import SDWebImageSwiftUI
import SwiftUI

struct ThumbnailView: View {
    var url: URL?
    private let thumbnails = ThumbnailsModel.shared

    var body: some View {
        viewForThumbnailExtension
    }

    var thumbnailExtension: String? {
        guard let url else { return nil }
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return urlComponents?.path.components(separatedBy: ".").last
    }

    @ViewBuilder var viewForThumbnailExtension: some View {
        if thumbnailExtension != nil {
            if thumbnailExtension == "webp" {
                webImage
            } else {
                asyncImageIfAvailable
            }
        } else {
            asyncImageIfAvailable
        }
    }

    var webImage: some View {
        WebImage(url: url)
            .resizable()
            .onFailure { _ in
                if let url {
                    thumbnails.insertUnloadable(url)
                }
            }
            .placeholder { placeholder }
    }

    @ViewBuilder var asyncImageIfAvailable: some View {
        if #available(iOS 15, macOS 12, *) {
            CachedAsyncImage(url: url, urlCache: BaseCacheModel.imageCache) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                case .failure:
                    placeholder.onAppear {
                        guard let url else { return }
                        thumbnails.insertUnloadable(url)
                    }
                default:
                    placeholder
                }
            }
        } else {
            webImage
        }
    }

    var placeholder: some View {
        Rectangle().fill(Color("PlaceholderColor"))
    }
}
