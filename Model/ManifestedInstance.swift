import Foundation

struct ManifestedInstance: Identifiable, Hashable {
    let id = UUID().uuidString
    let app: VideosApp
    let country: String
    let region: String
    let flag: String
    let url: URL

    var instance: Instance {
        .init(app: app, name: "Public - \(country)", apiURL: url.absoluteString)
    }

    var location: String {
        "\(flag) \(country)"
    }

    var anonymousAccount: Account {
        .init(
            id: UUID().uuidString,
            app: app,
            name: location,
            url: url.absoluteString,
            anonymous: true,
            country: country,
            region: region
        )
    }
}
