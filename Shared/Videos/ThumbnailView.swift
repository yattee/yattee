import SDWebImageSwiftUI
import SwiftUI

struct ThumbnailView: View {
    var url: URL?

    @ObservedObject private var imageManager = ImageManager()
    private var thumbnails = ThumbnailsModel.shared

    init(url: URL? = nil) {
        self.url = url
    }

    var body: some View {
        Group {
            if imageManager.image != nil {
                Group {
                    #if os(macOS)
                        Image(nsImage: imageManager.image!)
                            .resizable()
                    #else
                        Image(uiImage: imageManager.image!)
                            .resizable()
                    #endif
                }
            } else {
                Rectangle().fill(Color("PlaceholderColor"))
            }
        }
        .onAppear {
            guard let url else { return }

            self.imageManager.setOnFailure { _ in
                self.thumbnails.insertUnloadable(url)
            }
            self.imageManager.load(url: url)
        }
        .onDisappear { self.imageManager.cancel() }
    }
}
