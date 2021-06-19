import Alamofire
import Foundation
import SwiftyJSON

final class SubscriptionVideosProvider: DataProvider {
    @Published var videos = [Video]()

    let profile = Profile()

    func load() {
        let headers = HTTPHeaders([HTTPHeader(name: "Cookie", value: "SID=\(profile.sid)")])
        DataProvider.request("auth/feed", headers: headers).responseJSON { response in
            switch response.result {
            case let .success(value):
                if let feedVideos = JSON(value).dictionaryValue["videos"] {
                    self.videos = feedVideos.arrayValue.map { Video($0) }
                }
            case let .failure(error):
                print(error)
            }
        }
    }
}
