import Foundation

struct Chapter: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var image: URL?
    var start: Double
}
