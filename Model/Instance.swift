import Defaults
import Foundation

struct Instance: Defaults.Serializable, Hashable, Identifiable {
    struct Account: Defaults.Serializable, Hashable, Identifiable {
        static var bridge = AccountsBridge()
        static var empty = Account(instanceID: UUID(), name: "Signed Out", url: "", sid: "")

        let id: UUID
        let instanceID: UUID
        var name: String?
        let url: String
        let sid: String

        init(id: UUID? = nil, instanceID: UUID, name: String? = nil, url: String, sid: String) {
            self.id = id ?? UUID()
            self.instanceID = instanceID
            self.name = name
            self.url = url
            self.sid = sid
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

        var isEmpty: Bool {
            self == Account.empty
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(sid)
        }

        struct AccountsBridge: Defaults.Bridge {
            typealias Value = Account
            typealias Serializable = [String: String]

            func serialize(_ value: Value?) -> Serializable? {
                guard let value = value else {
                    return nil
                }

                return [
                    "id": value.id.uuidString,
                    "instanceID": value.instanceID.uuidString,
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

                let uuid = UUID(uuidString: id)
                let instanceUUID = UUID(uuidString: instanceID)!
                let name = object["name"] ?? ""

                return Account(id: uuid, instanceID: instanceUUID, name: name, url: url, sid: sid)
            }
        }
    }

    static var bridge = InstancesBridge()

    let id: UUID
    let name: String
    let url: String

    init(id: UUID? = nil, name: String, url: String) {
        self.id = id ?? UUID()
        self.name = name
        self.url = url
    }

    var description: String {
        name.isEmpty ? url : "\(name) (\(url))"
    }

    var shortDescription: String {
        name.isEmpty ? url : name
    }

    var anonymousAccount: Account {
        Account(instanceID: id, name: "Anonymous", url: url, sid: "")
    }

    struct InstancesBridge: Defaults.Bridge {
        typealias Value = Instance
        typealias Serializable = [String: String]

        func serialize(_ value: Value?) -> Serializable? {
            guard let value = value else {
                return nil
            }

            return [
                "id": value.id.uuidString,
                "name": value.name,
                "url": value.url
            ]
        }

        func deserialize(_ object: Serializable?) -> Value? {
            guard
                let object = object,
                let id = object["id"],
                let url = object["url"]
            else {
                return nil
            }

            let uuid = UUID(uuidString: id)
            let name = object["name"] ?? ""

            return Instance(id: uuid, name: name, url: url)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
