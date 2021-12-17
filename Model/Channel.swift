import AVFoundation
import Defaults
import Foundation
import SwiftyJSON

struct Channel: Identifiable, Hashable {
    var id: String
    var name: String
    var thumbnailURL: URL?
    var videos = [Video]()

    private var subscriptionsCount: Int?
    private var subscriptionsText: String?

    init(
        id: String,
        name: String,
        thumbnailURL: URL? = nil,
        subscriptionsCount: Int? = nil,
        subscriptionsText: String? = nil,
        videos: [Video] = []
    ) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.subscriptionsCount = subscriptionsCount
        self.subscriptionsText = subscriptionsText
        self.videos = videos
    }

    var detailsLoaded: Bool {
        !subscriptionsString.isNil
    }

    var subscriptionsString: String? {
        if subscriptionsCount != nil, subscriptionsCount! > 0 {
            return subscriptionsCount!.formattedAsAbbreviation()
        }

        return subscriptionsText
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
