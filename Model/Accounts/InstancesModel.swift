import Defaults
import Foundation

final class InstancesModel: ObservableObject {
    var all: [Instance] {
        Defaults[.instances]
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
        let instance = Instance(app: app, id: UUID().uuidString, name: name, url: url)
        Defaults[.instances].append(instance)

        return instance
    }

    static func remove(_ instance: Instance) {
        let accounts = InstancesModel.accounts(instance.id)
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            Defaults[.instances].remove(at: index)
            accounts.forEach { AccountsModel.remove($0) }
        }
    }
}
