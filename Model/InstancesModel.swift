import Defaults
import Foundation

final class InstancesModel: ObservableObject {
    var defaultAccount: Instance.Account! {
        Defaults[.instances].first?.accounts.first
    }

    func find(_ id: Instance.ID?) -> Instance? {
        guard id != nil else {
            return nil
        }

        return Defaults[.instances].first { $0.id == id }
    }

    func accounts(_ id: Instance.ID?) -> [Instance.Account] {
        find(id)?.accounts ?? []
    }

    func add(name: String, url: String) -> Instance {
        let instance = Instance(name: name, url: url)
        Defaults[.instances].append(instance)

        return instance
    }

    func remove(_ instance: Instance) {
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            Defaults[.instances].remove(at: index)
        }
    }

    func addAccount(instance: Instance, name: String, sid: String) -> Instance.Account {
        let account = Instance.Account(name: name, url: instance.url, sid: sid)

        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            Defaults[.instances][index].accounts.append(account)
        }

        return account
    }

    func removeAccount(instance: Instance, account: Instance.Account) {
        if let instanceIndex = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            if let accountIndex = Defaults[.instances][instanceIndex].accounts.firstIndex(where: { $0.id == account.id }) {
                Defaults[.instances][instanceIndex].accounts.remove(at: accountIndex)
            }
        }
    }
}
