import Alamofire
import Foundation
import SwiftyJSON

final class VideoDetailsProvider: DataProvider {
    @Published var video: Video?

    var id: String

    init(_ id: String) {
        self.id = id
        super.init()
    }

    func load() {
        DataProvider.request("videos/\(id)").responseJSON { response in
            switch response.result {
            case let .success(value):
                self.video = Video(JSON(value))
            case let .failure(error):
                print(error)
            }
        }
    }
}
