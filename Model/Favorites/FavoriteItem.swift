import Defaults
import Foundation

struct FavoriteItem: Codable, Equatable, Identifiable, Defaults.Serializable {
    enum Section: Codable, Equatable, Defaults.Serializable {
        case history
        case subscriptions
        case popular
        case trending(String, String?)
        case channel(String, String, String)
        case playlist(String, String)
        case channelPlaylist(String, String, String)
        case searchQuery(String, String, String, String)

        var label: String {
            switch self {
            case .history:
                return "History"
            case .subscriptions:
                return "Subscriptions"
            case .popular:
                return "Popular"
            case let .trending(country, category):
                let trendingCountry = Country(rawValue: country)!
                let trendingCategory = category.isNil ? nil : TrendingCategory(rawValue: category!)
                return "\(trendingCountry.flag) \(trendingCountry.id) \(trendingCategory?.name ?? "Trending")"
            case let .channel(_, _, name):
                return name
            case let .channelPlaylist(_, _, name):
                return name
            case let .searchQuery(text, date, duration, order):
                var label = "Search: \"\(text)\""
                if !date.isEmpty, let date = SearchQuery.Date(rawValue: date), date != .any {
                    label += " from \(date == .today ? date.name : " this \(date.name)")"
                }
                if !order.isEmpty, let order = SearchQuery.SortOrder(rawValue: order), order != .relevance {
                    label += " by \(order.name)"
                }
                if !duration.isEmpty {
                    label += " (\(duration))"
                }

                return label
            default:
                return ""
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.section == rhs.section
    }

    var id = UUID().uuidString
    var section: Section

    var widgetSettingsKey: String {
        "favorites-\(id)"
    }
}
