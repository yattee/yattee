import Defaults
import Foundation

struct FavoriteItem: Codable, Equatable, Identifiable, Defaults.Serializable {
    enum Section: Codable, Equatable, Defaults.Serializable {
        case subscriptions
        case popular
        case trending(String, String?)
        case channel(String, String)
        case playlist(String)
        case channelPlaylist(String, String)

        var label: String {
            switch self {
            case .subscriptions:
                return "Subscriptions"
            case .popular:
                return "Popular"
            case let .trending(country, category):
                let trendingCountry = Country(rawValue: country)!
                let trendingCategory = category.isNil ? nil : TrendingCategory(rawValue: category!)!
                return "\(trendingCountry.flag) \(trendingCategory?.name ?? "")"
            case let .channel(_, name):
                return name
            case let .channelPlaylist(_, name):
                return name
            default:
                return ""
            }
        }
    }

    static func == (lhs: FavoriteItem, rhs: FavoriteItem) -> Bool {
        lhs.section == rhs.section
    }

    var id = UUID().uuidString
    var section: Section
}
