import SwiftUI

struct NoDocumentsView: View {
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "doc")
                Text("No documents")
            }
            Text("Share files from Finder on a Mac\nor iTunes on Windows")
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(.secondary)
    }
}

struct NoDocumentsView_Previews: PreviewProvider {
    static var previews: some View {
        NoDocumentsView()
    }
}
