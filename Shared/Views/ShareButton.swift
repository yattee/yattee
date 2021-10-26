import SwiftUI

struct ShareButton: View {
    let contentItem: ContentItem
    @Binding var presentingShareSheet: Bool

    @EnvironmentObject<AccountsModel> private var accounts

    var body: some View {
        Button {
            #if os(iOS)
                presentingShareSheet = true
            #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shareURL, forType: .string)
            #endif
        } label: {
            #if os(iOS)
                Label("Share", systemImage: "square.and.arrow.up")
            #else
                EmptyView()
            #endif
        }
        .keyboardShortcut("c")
        .foregroundColor(.blue)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }

    private var shareURL: String {
        accounts.api.shareURL(contentItem).absoluteString
    }
}

struct ShareButton_Previews: PreviewProvider {
    static var previews: some View {
        ShareButton(contentItem: ContentItem(video: Video.fixture), presentingShareSheet: .constant(false))
    }
}
