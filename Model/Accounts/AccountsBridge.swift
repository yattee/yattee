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
            "instanceID": value.instanceID ?? "",
            "name": value.name ?? "",
            "apiURL": value.url,
            "username": value.username,
            "password": value.password ?? ""
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object = object,
            let id = object["id"],
            let instanceID = object["instanceID"],
            let url = object["apiURL"],
            let username = object["username"]
        else {
            return nil
        }

        let name = object["name"] ?? ""
        let password = object["password"]

        return Account(id: id, instanceID: instanceID, name: name, url: url, username: username, password: password)
    }
}
