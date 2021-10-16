import Defaults
import Foundation

final class InstancesModel: ObservableObject {
    @Published var defaultAccount: Instance.Account?

    var all: [Instance] {
        Defaults[.instances]
    }

    init() {
        guard let id = Defaults[.defaultAccountID] else {
            return
        }

        defaultAccount = findAccount(id)
    }

    func find(_ id: Instance.ID?) -> Instance? {
        guard id != nil else {
            return nil
        }

        return Defaults[.instances].first { $0.id == id }
    }

    func accounts(_ id: Instance.ID?) -> [Instance.Account] {
        Defaults[.accounts].filter { $0.instanceID == id }
    }

    func add(app: Instance.App, name: String, url: String) -> Instance {
        let instance = Instance(app: app, name: name, url: url)
        Defaults[.instances].append(instance)

        return instance
    }

    func remove(_ instance: Instance) {
        let accounts = accounts(instance.id)
        if let index = Defaults[.instances].firstIndex(where: { $0.id == instance.id }) {
            Defaults[.instances].remove(at: index)
            accounts.forEach { removeAccount($0) }
        }
    }

    func findAccount(_ id: Instance.Account.ID) -> Instance.Account? {
        Defaults[.accounts].first { $0.id == id }
    }

    func addAccount(instance: Instance, name: String, sid: String) -> Instance.Account {
        let account = Instance.Account(instanceID: instance.id, name: name, url: instance.url, sid: sid)
        Defaults[.accounts].append(account)

        return account
    }

    func removeAccount(_ account: Instance.Account) {
        if let accountIndex = Defaults[.accounts].firstIndex(where: { $0.id == account.id }) {
            Defaults[.accounts].remove(at: accountIndex)
        }
    }

    func setDefaultAccount(_ account: Instance.Account?) {
        Defaults[.defaultAccountID] = account?.id
        defaultAccount = account
    }

    func resetDefaultAccount() {
        setDefaultAccount(nil)
    }
}
