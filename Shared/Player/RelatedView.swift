import Defaults
import SwiftUI

struct RelatedView: View {
    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        LazyVStack {
            if let related = player.videoForDisplay?.related {
                Section(header: header) {
                    ForEach(related) { video in
                        PlayerQueueRow(item: PlayerQueueItem(video))
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                VideoContextMenuView(video: video)
                            }
                    }

                    Color.clear.padding(.bottom, 50)
                        .listRowBackground(Color.clear)
                        .backport
                        .listRowSeparator(false)
                }
            }
        }
        .environment(\.inNavigationView, false)
        #if os(macOS)
            .listStyle(.inset)
        #elseif os(iOS)
            .listStyle(.grouped)
            .backport
            .scrollContentBackground(false)
        #else
            .listStyle(.plain)
        #endif
    }

    var header: some View {
        Text("Related")
        #if !os(macOS)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

struct RelatedView_Previews: PreviewProvider {
    static var previews: some View {
        RelatedView()
            .injectFixtureEnvironmentObjects()
    }
}
