import Alamofire
import Foundation
import SwiftyJSON

final class PopluarVideosProvider: DataProvider {
    @Published var videos = [Video]()

    func load() {
        DataProvider.request("popular").responseJSON { response in
            switch response.result {
            case let .success(value):
                self.videos = JSON(value).arrayValue.map { Video($0) }
            case let .failure(error):
                print(error)
            }
        }
    }
}
