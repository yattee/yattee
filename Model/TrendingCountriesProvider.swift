import Alamofire
import Foundation
import SwiftyJSON

final class TrendingCountriesProvider: DataProvider {
    @Published var countries = [Country]()

    private var query: String = ""

    func load(_ query: String) {
        guard query != self.query else {
            return
        }

        self.query = query
        countries = Country.searchByName(query)
    }
}
