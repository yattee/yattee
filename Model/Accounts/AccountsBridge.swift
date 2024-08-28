import Defaults
import Foundation

struct AccountsBridge: Defaults.Bridge {
    typealias Value = Account
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else {
            return nil
        }

        // Parse the urlString to check for embedded username and password
        var sanitizedUrlString = value.urlString
        if var urlComponents = URLComponents(string: value.urlString) {
            if let user = urlComponents.user, let password = urlComponents.password {
                // Sanitize the embedded username and password
                let sanitizedUser = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
                let sanitizedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password

                // Update the URL components with sanitized credentials
                urlComponents.user = sanitizedUser
                urlComponents.password = sanitizedPassword

                // Reconstruct the sanitized URL
                sanitizedUrlString = urlComponents.string ?? value.urlString
            }
        }

        return [
            "id": value.id,
            "instanceID": value.instanceID ?? "",
            "name": value.name,
            "apiURL": sanitizedUrlString,
            "username": value.username,
            "password": value.password ?? ""
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object,
            let id = object["id"],
            let instanceID = object["instanceID"],
            let url = object["apiURL"],
            let username = object["username"]
        else {
            return nil
        }

        let name = object["name"] ?? ""
        let password = object["password"]

        return Account(id: id, instanceID: instanceID, name: name, urlString: url, username: username, password: password)
    }
}
