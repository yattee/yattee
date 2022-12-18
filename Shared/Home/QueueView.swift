import SwiftUI

struct QueueView: View {
    @State private var expanded = false

    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        LazyVStack {
            if !items.isEmpty {
                HStack {
                    sectionLabel("Next in queue")
                    Button {
                        withAnimation {
                            expanded.toggle()
                        }
                    } label: {
                        Label("Show more", systemImage: expanded ? "chevron.up" : "chevron.down")
                            .animation(nil, value: expanded)
                            .foregroundColor(.accentColor)
                            .imageScale(.large)
                            .labelStyle(.iconOnly)
                    }
                    .opacity(items.count > 1 ? 1 : 0)
                }
                ForEach(limitedItems) { item in
                    ContentItemView(item: .init(video: item.video))
                        .environment(\.listingStyle, .list)
                        .environment(\.inQueueListing, true)
                        .environment(\.noListingDividers, limit == 1)
                        .transition(.opacity)
                }
            }
        }
    }

    var limitedItems: [PlayerQueueItem] {
        if let limit {
            return Array(items.prefix(limit))
        }

        return items
    }

    var items: [PlayerQueueItem] {
        player.queue
    }

    var limit: Int? {
        if !expanded {
            return 1
        }

        return nil
    }

    func sectionLabel(_ label: String) -> some View {
        Text(label.localized())
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)
    }
}

struct QueueView_Previews: PreviewProvider {
    static var previews: some View {
        QueueView()
    }
}
