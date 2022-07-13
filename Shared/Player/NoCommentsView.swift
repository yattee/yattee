import SwiftUI

struct NoCommentsView: View {
    var text: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))

            Text(text)
            #if !os(tvOS)
                .font(.system(size: 12))
            #endif
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        #if !os(tvOS)
            .foregroundColor(.secondary)
        #endif
    }
}

struct NoCommentsView_Previews: PreviewProvider {
    static var previews: some View {
        NoCommentsView(text: "No comments", systemImage: "xmark.circle.fill")
    }
}
