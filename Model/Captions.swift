import Foundation

struct Captions: Hashable, Identifiable {
    var id = UUID().uuidString
    let label: String
    let code: String
    let url: URL

    var description: String {
        "\(label) (\(code))"
    }
}
