import Alamofire
import Foundation
import SwiftyJSON

final class SubscriptionVideosProvider: DataProvider {
    @Published var videos = [Video]()

    var sid: String = "RpoS7YPPK2-QS81jJF9z4KSQAjmzsOnMpn84c73-GQ8="

    func load() {
        let headers = HTTPHeaders([HTTPHeader(name: "Cookie", value: "SID=\(sid)")])
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
