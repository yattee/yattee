import Defaults
import Foundation

struct Instance: Defaults.Serializable, Hashable, Identifiable {
    struct Account: Defaults.Serializable, Hashable, Identifiable {
        static var bridge = AccountsBridge()

        let id: UUID?
        var name: String?
        let url: String
        let sid: String

        init(id: UUID? = nil, name: String? = nil, url: String, sid: String) {
            self.id = id ?? UUID()
            self.name = name
            self.url = url
            self.sid = sid
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

    struct AccountsBridge: Defaults.Bridge {
        typealias Value = Account
        typealias Serializable = [String: String]

        func serialize(_ value: Value?) -> Serializable? {
            guard let value = value else {
                return nil
            }

            return [
                "id": value.id?.uuidString ?? "",
                "name": value.name ?? "",
                "url": value.url,
                "sid": value.sid
            ]
        }

        func deserialize(_ object: Serializable?) -> Value? {
            guard
                let object = object,
                let url = object["url"],
                let sid = object["sid"]
            else {
                return nil
            }

            let name = object["name"] ?? ""

            return Account(name: name, url: url, sid: sid)
        }
    }

    static var bridge = InstancesBridge()

    let id: UUID?
    let name: String
    let url: String
    var accounts = [Account]()

    init(id: UUID? = nil, name: String, url: String, accounts: [Account] = []) {
        self.id = id ?? UUID()
        self.name = name
        self.url = url
        self.accounts = accounts
    }

    var description: String {
        name.isEmpty ? url : "\(name) (\(url))"
    }

    var shortDescription: String {
        name.isEmpty ? url : name
    }

    var anonymousAccount: Account {
        Account(name: "Anonymous", url: url, sid: "")
    }

    struct InstancesBridge: Defaults.Bridge {
        typealias Value = Instance
        typealias Serializable = [String: String]

        func serialize(_ value: Value?) -> Serializable? {
            guard let value = value else {
                return nil
            }

            return [
                "id": value.id?.uuidString ?? "",
                "name": value.name,
                "url": value.url,
                "accounts": value.accounts.map { "\($0.id!):\($0.name ?? ""):\($0.sid)" }.joined(separator: ";")
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

            let name = object["name"] ?? ""
            let accounts = object["accounts"] ?? ""
            let uuid = UUID(uuidString: id)

            var instance = Instance(id: uuid, name: name, url: url)

            accounts.split(separator: ";").forEach { sid in
                let components = sid.components(separatedBy: ":")

                let id = components[0]
                let name = components[1]
                let sid = components[2]

                let uuid = UUID(uuidString: id)
                instance.accounts.append(Account(id: uuid, name: name, url: instance.url, sid: sid))
            }

            return instance
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
