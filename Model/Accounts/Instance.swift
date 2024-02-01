import Defaults
import Foundation

struct Instance: Defaults.Serializable, Hashable, Identifiable {
    static var bridge = InstancesBridge()

    let app: VideosApp
    let id: String
    let name: String
    let apiURLString: String
    var frontendURL: String?
    var proxiesVideos: Bool

    init(app: VideosApp, id: String? = nil, name: String? = nil, apiURLString: String, frontendURL: String? = nil, proxiesVideos: Bool = false) {
        self.app = app
        self.id = id ?? UUID().uuidString
        self.name = name ?? app.rawValue
        self.apiURLString = apiURLString
        self.frontendURL = frontendURL
        self.proxiesVideos = proxiesVideos
    }

    var apiURL: URL! {
        URL(string: apiURLString)
    }

    var anonymous: VideosAPI! {
        switch app {
        case .invidious:
            return InvidiousAPI(account: anonymousAccount)
        case .piped:
            return PipedAPI(account: anonymousAccount)
        case .peerTube:
            return PeerTubeAPI(account: anonymousAccount)
        case .local:
            return nil
        }
    }

    var description: String {
        "\(app.name) - \(shortDescription)"
    }

    var longDescription: String {
        name.isEmpty ? "\(app.name) - \(apiURLString)" : "\(app.name) - \(name) (\(apiURLString))"
    }

    var shortDescription: String {
        name.isEmpty ? apiURLString : name
    }

    var anonymousAccount: Account {
        Account(instanceID: id, name: "Anonymous".localized(), urlString: apiURLString, anonymous: true)
    }

    var urlComponents: URLComponents {
        URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
    }

    var frontendHost: String? {
        guard let url = app == .invidious ? apiURLString : frontendURL else {
            return nil
        }

        return URLComponents(string: url)?.host
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(apiURL)
    }

    var accounts: [Account] {
        AccountsModel.shared.all.filter { $0.instanceID == id }
    }
}
