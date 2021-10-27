import Defaults
import Foundation

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
            "apiURL": value.url,
            "sid": value.sid
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object = object,
            let id = object["id"],
            let instanceID = object["instanceID"],
            let url = object["apiURL"],
            let sid = object["sid"]
        else {
            return nil
        }

        let name = object["name"] ?? ""

        return Account(id: id, instanceID: instanceID, name: name, url: url, sid: sid)
    }
}
