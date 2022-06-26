import Defaults
import Foundation

final class InstancesModel: ObservableObject {
    static var all: [Instance] {
        Defaults[.instances]
    }

    static var forPlayer: Instance? {
        guard let id = Defaults[.playerInstanceID] else {
            return nil
        }

        return InstancesModel.find(id)
    }

    var lastUsed: Instance? {
        guard let id = Defaults[.lastInstanceID] else {
            return nil
        }

        return InstancesModel.find(id)
    }

    static func find(_ id: Instance.ID?) -> Instance? {
        guard id != nil else {
            return nil
        }

        return Defaults[.instances].first { $0.id == id }
    }

    static func accounts(_ id: Instance.ID?) -> [Account] {
        Defaults[.accounts].filter { $0.instanceID == id }
    }

    static func add(app: VideosApp, name: String, url: String) -> Instance {
        let instance = Instance(
            app: app, id: UUID().uuidString, name: name, apiURL: standardizedURL(url)
        )
        Defaults[.instances].append(instance)

        return instance
    }

    static func setFrontendURL(_ instance: Instance, _ url: String) {
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            var instance = Defaults[.instances][index]
            instance.frontendURL = standardizedURL(url)

            Defaults[.instances][index] = instance
        }
    }

    static func remove(_ instance: Instance) {
        let accounts = Self.accounts(instance.id)
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            Defaults[.instances].remove(at: index)
            accounts.forEach { AccountsModel.remove($0) }
        }
    }

    static func standardizedURL(_ url: String) -> String {
        if url.count > 7, url.last == "/" {
            return String(url.dropLast())
        } else {
            return url
        }
    }
}
