import Defaults
import Foundation

struct Account: Defaults.Serializable, Hashable, Identifiable {
    static var bridge = AccountsBridge()

    let id: String
    let instanceID: String
    var name: String?
    let url: String
    let username: String
    let password: String?
    var token: String?
    let anonymous: Bool

    init(
        id: String? = nil,
        instanceID: String? = nil,
        name: String? = nil,
        url: String? = nil,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        anonymous: Bool = false
    ) {
        self.anonymous = anonymous

        self.id = id ?? (anonymous ? "anonymous-\(instanceID!)" : UUID().uuidString)
        self.instanceID = instanceID ?? UUID().uuidString
        self.name = name
        self.url = url ?? ""
        self.username = username ?? ""
        self.token = token
        self.password = password ?? ""
    }

    var instance: Instance! {
        Defaults[.instances].first { $0.id == instanceID }
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
