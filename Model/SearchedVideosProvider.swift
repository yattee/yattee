import Foundation
import SwiftyJSON

class SearchedVideosProvider: DataProvider {
    @Published var videos = [Video]()
    var query: String = ""

    func load() {
        let searchPath = "search?q=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        DataProvider.request(searchPath).responseJSON { response in
            switch response.result {
            case let .success(value):
                self.videos = JSON(value).arrayValue.map { Video($0) }
            case let .failure(error):
                print(error)
            }
        }
    }
}
