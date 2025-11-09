import CachedAsyncImage
import SDWebImageSwiftUI
import SwiftUI

struct ThumbnailView: View {
    var url: URL?
    private let thumbnails = ThumbnailsModel.shared
    private let thumbnailExtension: String?

    init(url: URL?) {
        self.url = url
        self.thumbnailExtension = Self.extractExtension(from: url)
    }

    private static func extractExtension(from url: URL?) -> String? {
        guard let url,
              let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let pathComponents = urlComponents.path.components(separatedBy: ".")
        guard pathComponents.count > 1 else { return nil }

        return pathComponents.last
    }

    var body: some View {
        if url != nil {
            viewForThumbnailExtension
        } else {
            placeholder
        }
    }

    @ViewBuilder var viewForThumbnailExtension: some View {
        if AccountsModel.shared.app != .piped, thumbnailExtension != nil {
            if thumbnailExtension == "webp" {
                webImage
            } else {
                asyncImageIfAvailable
            }
        } else {
            webImage
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
        // swiftlint:disable:next deployment_target
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
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
            placeholder
        }
    }

    var placeholder: some View {
        Rectangle().fill(Color("PlaceholderColor"))
    }
}
