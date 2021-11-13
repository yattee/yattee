import Defaults
import Foundation

struct Instance: Defaults.Serializable, Hashable, Identifiable {
    static var bridge = InstancesBridge()

    let app: VideosApp
    let id: String
    let name: String
    let apiURL: String
    let username: String?
    let password: String?
    var frontendURL: String?

    init(app: VideosApp, id: String? = nil, name: String, apiURL: String, frontendURL: String? = nil) {
        self.app = app
        self.id = id ?? UUID().uuidString
        self.name = name
        self.apiURL = apiURL
        self.username = apiURL.url?.user
        self.password = apiURL.url?.password
        self.frontendURL = frontendURL
    }

    var anonymous: VideosAPI {
        switch app {
        case .invidious:
            return InvidiousAPI(account: anonymousAccount)
        case .piped:
            return PipedAPI(account: anonymousAccount)
        }
    }

    var description: String {
        "\(app.name) - \(shortDescription)"
    }

    var longDescription: String {
        name.isEmpty ? "\(app.name) - \(apiURL)" : "\(app.name) - \(name) (\(apiURL))"
    }

    var shortDescription: String {
        name.isEmpty ? apiURL : name
    }

    var anonymousAccount: Account {
        Account(instanceID: id, name: "Anonymous", url: apiURL, anonymous: true)
    }

    var urlComponents: URLComponents {
        URLComponents(string: apiURL)!
    }

    var frontendHost: String? {
        guard let url = app == .invidious ? apiURL : frontendURL else {
            return nil
        }

        return URLComponents(string: url)?.host
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(apiURL)
    }
}
