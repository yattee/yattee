import Defaults
import Foundation

struct Account: Defaults.Serializable, Hashable, Identifiable {
    struct AccountsBridge: Defaults.Bridge {
        typealias Value = Account
        typealias Serializable = [String: String]

        func serialize(_ value: Value?) -> Serializable? {
            guard let value = value else {
                return nil
            }

            return [
                "id": value.id,
                "instanceID": value.instanceID,
                "name": value.name ?? "",
                "url": value.url,
                "sid": value.sid
            ]
        }

        func deserialize(_ object: Serializable?) -> Value? {
            guard
                let object = object,
                let id = object["id"],
                let instanceID = object["instanceID"],
                let url = object["url"],
                let sid = object["sid"]
            else {
                return nil
            }

            let name = object["name"] ?? ""

            return Account(id: id, instanceID: instanceID, name: name, url: url, sid: sid)
        }
    }

    static var bridge = AccountsBridge()

    let id: String
    let instanceID: String
    var name: String?
    let url: String
    let sid: String
    let anonymous: Bool

    init(id: String? = nil, instanceID: String? = nil, name: String? = nil, url: String? = nil, sid: String? = nil, anonymous: Bool = false) {
        self.anonymous = anonymous

        self.id = id ?? (anonymous ? "anonymous-\(instanceID!)" : UUID().uuidString)
        self.instanceID = instanceID ?? UUID().uuidString
        self.name = name
        self.url = url ?? ""
        self.sid = sid ?? ""
    }

    var instance: Instance {
        Defaults[.instances].first { $0.id == instanceID }!
    }

    var anonymizedSID: String {
        guard sid.count > 3 else {
            return ""
        }

        let index = sid.index(sid.startIndex, offsetBy: 4)
        return String(sid[..<index])
    }

    var description: String {
        (name != nil && name!.isEmpty) ? "Unnamed (\(anonymizedSID))" : name!
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sid)
    }
}
