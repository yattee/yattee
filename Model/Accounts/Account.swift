import Defaults
import Foundation

struct Account: Defaults.Serializable, Hashable, Identifiable {
    static var bridge = AccountsBridge()

    let id: String
    let app: VideosApp
    let instanceID: String?
    var name: String?
    let url: String
    let username: String
    let password: String?
    var token: String?
    let anonymous: Bool
    let country: String?
    let region: String?

    init(
        id: String? = nil,
        app: VideosApp? = nil,
        instanceID: String? = nil,
        name: String? = nil,
        url: String? = nil,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        anonymous: Bool = false,
        country: String? = nil,
        region: String? = nil
    ) {
        self.anonymous = anonymous

        self.id = id ?? (anonymous ? "anonymous-\(instanceID ?? url ?? UUID().uuidString)" : UUID().uuidString)
        self.app = app ?? .invidious
        self.instanceID = instanceID
        self.name = name
        self.url = url ?? ""
        self.username = username ?? ""
        self.token = token
        self.password = password ?? ""
        self.country = country
        self.region = region
    }

    var instance: Instance! {
        Defaults[.instances].first { $0.id == instanceID } ?? Instance(app: app, name: url, apiURL: url)
    }

    var isPublic: Bool {
        instanceID.isNil
    }

    var shortUsername: String {
        guard username.count > 10 else {
            return username
        }

        let index = username.index(username.startIndex, offsetBy: 11)
        return String(username[..<index])
    }

    var description: String {
        (name != nil && name!.isEmpty) ? shortUsername : name!
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(username)
    }
}
