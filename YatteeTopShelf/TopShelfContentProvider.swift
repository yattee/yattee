import TVServices

class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (any TVTopShelfContent) -> Void) {
        let defaults = AppGroup.defaults
        let enabled = TopShelfSnapshot.enabledSections(from: defaults)

        let collections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = enabled.compactMap { section in
            let items = TopShelfSnapshot.read(section: section, from: defaults)
            guard !items.isEmpty else { return nil }
            let sectioned = items.map { makeItem(from: $0, in: section) }
            let collection = TVTopShelfItemCollection(items: sectioned)
            collection.title = section.localizedTitle
            return collection
        }

        completionHandler(TVTopShelfSectionedContent(sections: collections))
    }

    private func makeItem(from item: TopShelfItem, in section: TopShelfSection) -> TVTopShelfSectionedItem {
        let sectioned = TVTopShelfSectionedItem(identifier: "\(section.rawValue).\(item.videoID)")
        sectioned.title = item.title
        sectioned.imageShape = .hdtv
        if let url = item.thumbnailURL.flatMap(URL.init(string:)) {
            sectioned.setImageURL(url, for: .screenScale1x)
            sectioned.setImageURL(url, for: .screenScale2x)
        }
        if let deepLink = URL(string: item.deepLinkURL) {
            sectioned.displayAction = TVTopShelfAction(url: deepLink)
            sectioned.playAction = TVTopShelfAction(url: deepLink)
        }
        if section == .continueWatching,
           let progress = item.progressSeconds, item.duration > 0 {
            sectioned.playbackProgress = max(0, min(1, progress / item.duration))
        }
        return sectioned
    }
}
