import Alamofire
import Foundation
import SwiftyJSON

final class SponsorBlockSegmentsProvider: ObservableObject {
    static let categories = ["sponsor", "selfpromo", "outro", "intro", "music_offtopic", "interaction"]

    @Published var video: Video?

    @Published var segments = [Segment]()

    var id: String

    init(_ id: String) {
        self.id = id
    }

    func load() {
        AF.request("https://sponsor.ajay.app/api/skipSegments", parameters: parameters).responseJSON { response in
            switch response.result {
            case let .success(value):
                self.segments = JSON(value).arrayValue.map { SponsorBlockSegment($0) }
            case let .failure(error):
                print(error)
            }
        }
    }

    private var parameters: [String: String] {
        [
            "videoID": id,
            "categories": JSON(SponsorBlockSegmentsProvider.categories).rawString(String.Encoding.utf8)!,
        ]
    }
}
