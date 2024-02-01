import Defaults
import Foundation

final class InstancesModel: ObservableObject {
    static var shared = InstancesModel()

    var all: [Instance] {
        Defaults[.instances]
    }

    var forPlayer: Instance? {
        guard let id = Defaults[.playerInstanceID] else {
            return nil
        }

        return Self.shared.find(id)
    }

    var lastUsed: Instance? {
        guard let id = Defaults[.lastInstanceID] else {
            return nil
        }

        return Self.shared.find(id)
    }

    func find(_ id: Instance.ID?) -> Instance? {
        guard id != nil else {
            return nil
        }

        return Defaults[.instances].first { $0.id == id }
    }

    func findByURLString(_ urlString: String?) -> Instance? {
        guard let urlString else { return nil }

        return Defaults[.instances].first { $0.apiURLString == urlString }
    }

    func accounts(_ id: Instance.ID?) -> [Account] {
        Defaults[.accounts].filter { $0.instanceID == id }
    }

    func add(id: String? = UUID().uuidString, app: VideosApp, name: String, url: String) -> Instance {
        let instance = Instance(
            app: app, id: id, name: name, apiURLString: standardizedURL(url)
        )
        Defaults[.instances].append(instance)

        return instance
    }

    func insert(id: String? = UUID().uuidString, app: VideosApp, name: String, url: String) -> Instance {
        if let instance = Defaults[.instances].first(where: { $0.apiURL.absoluteString == standardizedURL(url) }) {
            return instance
        }

        return add(id: id, app: app, name: name, url: url)
    }

    func setFrontendURL(_ instance: Instance, _ url: String) {
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            var instance = Defaults[.instances][index]
            instance.frontendURL = standardizedURL(url)

            Defaults[.instances][index] = instance
        }
    }

    func setProxiesVideos(_ instance: Instance, _ proxiesVideos: Bool) {
        guard let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) else {
            return
        }

        var instance = Defaults[.instances][index]
        instance.proxiesVideos = proxiesVideos

        Defaults[.instances][index] = instance
    }

    func remove(_ instance: Instance) {
        let accounts = accounts(instance.id)
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            Defaults[.instances].remove(at: index)
            accounts.forEach { AccountsModel.remove($0) }
        }
    }

    func standardizedURL(_ url: String) -> String {
        if url.count > 7, url.last == "/" {
            return String(url.dropLast())
        }
        return url
    }
}
