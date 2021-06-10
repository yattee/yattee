import SwiftUI
import URLImage
import URLImageStore

@main
struct PearvidiousApp: App {
    var body: some Scene {
        let urlImageService = URLImageService(fileStore: URLImageFileStore(),
                                              inMemoryStore: URLImageInMemoryStore())
        WindowGroup {
            ContentView()
                .environment(\.urlImageService, urlImageService)
        }
    }
}
