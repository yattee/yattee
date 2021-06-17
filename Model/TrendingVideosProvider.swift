import Alamofire
import Foundation
import SwiftUI
import SwiftyJSON

final class TrendingVideosProvider: DataProvider {
    @Published var videos = [Video]()

    var currentCategory: TrendingCategory?
    var currentCountry: Country?

    func load(category: TrendingCategory, country: Country) {
        if category == currentCategory, country == currentCountry {
            return
        }

        DataProvider.request("trending?type=\(category.name)&region=\(country.rawValue)").responseJSON { response in
            switch response.result {
            case let .success(value):
                self.videos = JSON(value).arrayValue.map { Video($0) }
            case let .failure(error):
                print(error)
            }
        }

        currentCategory = category
        currentCountry = country

        videos = []
    }
}
