import Defaults
import Foundation

struct Account: Defaults.Serializable, Hashable, Identifiable {
    static var bridge = AccountsBridge()

    let id: String
    var app: VideosApp?
    let instanceID: String?
    var name: String
    let urlString: String
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
        urlString: String? = nil,
        username: String? = nil,
        password: String? = nil,
        anonymous: Bool = false,
        country: String? = nil,
        region: String? = nil
    ) {
        self.anonymous = anonymous

        self.id = id ?? (anonymous ? "anonymous-\(instanceID ?? urlString ?? UUID().uuidString)" : UUID().uuidString)
        self.instanceID = instanceID
        self.name = name ?? ""
        self.urlString = urlString ?? ""
        self.username = username ?? ""
        self.password = password ?? ""
        self.country = country
        self.region = region
        self.app = app ?? instance.app
    }

    var url: URL! {
        URL(string: urlString)
    }

    var token: String? {
        KeychainModel.shared.getAccountKey(self, "token")
    }

    var credentials: (String?, String?) {
        AccountsModel.getCredentials(self)
    }

    var instance: Instance! {
        InstancesModel.shared.find(instanceID) ?? Instance(app: app ?? .invidious, name: urlString, apiURLString: urlString)
    }

    var isPublic: Bool {
        instanceID.isNil
    }

    var isPublicAddedToCustom: Bool {
        InstancesModel.shared.findByURLString(urlString) != nil
    }

    var description: String {
        guard !isPublic else {
            return name
        }

        let (username, _) = credentials
        return username ?? name
    }

    var urlHost: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? ""
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(username)
    }

    var feedCacheKey: String {
        "feed-\(id)"
    }
}
