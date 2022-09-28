import Defaults
import Foundation

struct Account: Defaults.Serializable, Hashable, Identifiable {
    static var bridge = AccountsBridge()

    let id: String
    var app: VideosApp?
    let instanceID: String?
    var name: String?
    let url: String
    var username: String
    var password: String?
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
        anonymous: Bool = false,
        country: String? = nil,
        region: String? = nil
    ) {
        self.anonymous = anonymous

        self.id = id ?? (anonymous ? "anonymous-\(instanceID ?? url ?? UUID().uuidString)" : UUID().uuidString)
        self.instanceID = instanceID
        self.name = name
        self.url = url ?? ""
        self.username = username ?? ""
        self.password = password ?? ""
        self.country = country
        self.region = region
        self.app = app ?? instance.app
    }

    var token: String? {
        KeychainModel.shared.getAccountKey(self, "token")
    }

    var credentials: (String?, String?) {
        AccountsModel.getCredentials(self)
    }

    var instance: Instance! {
        Defaults[.instances].first { $0.id == instanceID } ?? Instance(app: app ?? .invidious, name: url, apiURL: url)
    }

    var isPublic: Bool {
        instanceID.isNil
    }

    var shortUsername: String {
        let (username, _) = credentials

        guard let username,
              username.count > 10
        else {
            return username ?? ""
        }

        let index = username.index(username.startIndex, offsetBy: 11)
        return String(username[..<index])
    }

    var description: String {
        guard let name, !name.isEmpty else {
            return shortUsername
        }

        return name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(username)
    }
}
