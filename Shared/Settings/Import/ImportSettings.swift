import SwiftUI

struct ImportSettings: View {
    @State private var fileURL = ""

    var body: some View {
        VStack(spacing: 100) {
            VStack(alignment: .leading, spacing: 20) {
                Text("1. Export settings from Yattee for iOS or macOS")
                Text("2. Upload it to a file hosting (e. g. Pastebin or GitHub Gist)")
                Text("3. Enter file URL in the field below. You can use iOS remote to paste.")
            }

            TextField("URL", text: $fileURL)

            Button {
                if let url = URL(string: fileURL) {
                    NavigationModel.shared.presentSettingsImportSheet(url)
                }
            } label: {
                Text("Import")
            }
        }
        .padding(20)
        .navigationTitle("Import Settings")
    }
}

struct ImportSettings_Previews: PreviewProvider {
    static var previews: some View {
        ImportSettings()
    }
}
