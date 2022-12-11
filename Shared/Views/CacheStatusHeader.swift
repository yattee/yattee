import SwiftUI

struct CacheStatusHeader: View {
    var refreshTime: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(Constants.progressViewScale, anchor: .center)
                .opacity(isLoading ? 1 : 0)
            Text(refreshTime)
        }
        .font(.caption.monospacedDigit())
        .foregroundColor(.secondary)
    }
}

struct CacheStatusHeader_Previews: PreviewProvider {
    static var previews: some View {
        CacheStatusHeader(refreshTime: "15:10:20")
    }
}
