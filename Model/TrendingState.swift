import Foundation

final class TrendingState: ObservableObject {
    @Published var category: TrendingCategory = .default
    @Published var country: Country = .pl
}
