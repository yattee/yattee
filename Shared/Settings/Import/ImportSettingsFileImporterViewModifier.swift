import Foundation
import SwiftUI

struct ImportSettingsFileImporterViewModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                do {
                    let selectedFile = try result.get()
                    var urlToOpen: URL?

                    if let bookmarkURL = URLBookmarkModel.shared.loadBookmark(selectedFile) {
                        urlToOpen = bookmarkURL
                    }

                    if selectedFile.startAccessingSecurityScopedResource() {
                        URLBookmarkModel.shared.saveBookmark(selectedFile)
                        urlToOpen = selectedFile
                    }

                    guard let urlToOpen else { return }
                    NavigationModel.shared.presentSettingsImportSheet(urlToOpen, forceSettings: true)
                } catch {
                    NavigationModel.shared.presentAlert(title: "Could not open Files")
                }
            }
    }
}
