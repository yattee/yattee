import Defaults
import SwiftUI

struct RelatedView: View {
    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        List {
            if let related = player.currentVideo?.related {
                Section(header: Text("Related")) {
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
}

struct RelatedView_Previews: PreviewProvider {
    static var previews: some View {
        RelatedView()
            .injectFixtureEnvironmentObjects()
    }
}
