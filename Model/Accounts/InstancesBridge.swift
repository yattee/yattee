import Defaults
import Foundation

struct InstancesBridge: Defaults.Bridge {
    typealias Value = Instance
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else {
            return nil
        }

        return [
            "app": value.app.rawValue,
            "id": value.id,
            "name": value.name,
            "apiURL": value.apiURLString,
            "frontendURL": value.frontendURL ?? "",
            "proxiesVideos": value.proxiesVideos ? "true" : "false",
            "invidiousCompanion": value.invidiousCompanion ? "true" : "false"
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object,
            let app = VideosApp(rawValue: object["app"] ?? ""),
            let id = object["id"],
            let apiURL = object["apiURL"]
        else {
            return nil
        }

        let name = object["name"] ?? ""
        let frontendURL: String? = object["frontendURL"]!.isEmpty ? nil : object["frontendURL"]
        let proxiesVideos = object["proxiesVideos"] == "true"
        let invidiousCompanion = object["invidiousCompanion"] == "true"

        return Instance(app: app, id: id, name: name, apiURLString: apiURL, frontendURL: frontendURL, proxiesVideos: proxiesVideos, invidiousCompanion: invidiousCompanion)
    }
}
