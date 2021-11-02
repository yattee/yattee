import SwiftUI

struct RelatedView: View {
    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        List {
            if !player.currentVideo.isNil, !player.currentVideo!.related.isEmpty {
                Section(header: Text("Related")) {
                    ForEach(player.currentVideo!.related) { video in
                        PlayerQueueRow(item: PlayerQueueItem(video), fullScreen: .constant(false))
                    }
                }
            }
        }
        #if os(macOS)
            .listStyle(.inset)
        #elseif os(iOS)
            .listStyle(.grouped)
        #else
            .listStyle(.plain)
        #endif
    }
}

struct RelatedView_Previews: PreviewProvider {
    static var previews: some View {
        RelatedView()
    }
}
