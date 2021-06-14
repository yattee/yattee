import Foundation
import SwiftyJSON

final class ChannelVideosProvider: DataProvider {
    @Published var videos = [Video]()

    var channelID: String? = ""

    func load() {
        guard channelID != nil else {
            return
        }

        let searchPath = "channels/\(channelID!)"
        DataProvider.request(searchPath).responseJSON { response in
            switch response.result {
            case let .success(value):
                if let channelVideos = JSON(value).dictionaryValue["latestVideos"] {
                    self.videos = channelVideos.arrayValue.map { Video($0) }
                }
            case let .failure(error):
                print(error)
            }
        }
    }
}
