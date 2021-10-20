import Defaults
import Foundation

struct Instance: Defaults.Serializable, Hashable, Identifiable {
    struct InstancesBridge: Defaults.Bridge {
        typealias Value = Instance
        typealias Serializable = [String: String]

        func serialize(_ value: Value?) -> Serializable? {
            guard let value = value else {
                return nil
            }

            return [
                "app": value.app.rawValue,
                "id": value.id,
                "name": value.name,
                "url": value.url
            ]
        }

        func deserialize(_ object: Serializable?) -> Value? {
            guard
                let object = object,
                let app = VideosApp(rawValue: object["app"] ?? ""),
                let id = object["id"],
                let url = object["url"]
            else {
                return nil
            }

            let name = object["name"] ?? ""

            return Instance(app: app, id: id, name: name, url: url)
        }
    }

    static var bridge = InstancesBridge()

    let app: VideosApp
    let id: String
    let name: String
    let url: String

    init(app: VideosApp, id: String? = nil, name: String, url: String) {
        self.app = app
        self.id = id ?? UUID().uuidString
        self.name = name
        self.url = url
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
        name.isEmpty ? "\(app.name) - \(url)" : "\(app.name) - \(name) (\(url))"
    }

    var shortDescription: String {
        name.isEmpty ? url : name
    }

    var anonymousAccount: Account {
        Account(instanceID: id, name: "Anonymous", url: url, anonymous: true)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
