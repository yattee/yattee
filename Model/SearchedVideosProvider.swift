import Foundation
import SwiftyJSON

final class SearchedVideosProvider: DataProvider {
    @Published var videos = [Video]()

    var currentQuery: String = ""

    func load(_ query: String) {
        var newQuery = query

        if let url = URLComponents(string: query),
           let queryItem = url.queryItems?.first(where: { item in item.name == "v" }),
           let id = queryItem.value
        {
            newQuery = id
        }

        if newQuery == currentQuery {
            return
        }

        currentQuery = newQuery

        let searchPath = "search?q=\(currentQuery.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
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
