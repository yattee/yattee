import Defaults
import SwiftyJSON

struct LocationsSettingsGroupImporter {
    var json: JSON

    var includePublicLocations = true
    var includedInstancesIDs = Set<Instance.ID>()
    var includedAccountsIDs = Set<Account.ID>()
    var includedAccountsPasswords = [Account.ID: String]()

    init(
        json: JSON,
        includePublicLocations: Bool = true,
        includedInstancesIDs: Set<Instance.ID> = [],
        includedAccountsIDs: Set<Account.ID> = [],
        includedAccountsPasswords: [Account.ID: String] = [:]
    ) {
        self.json = json
        self.includePublicLocations = includePublicLocations
        self.includedInstancesIDs = includedInstancesIDs
        self.includedAccountsIDs = includedAccountsIDs
        self.includedAccountsPasswords = includedAccountsPasswords
    }

    var instances: [Instance] {
        if let instances = json["instances"].array {
            return instances.compactMap { instanceJSON in
                let dict = instanceJSON.dictionaryValue.mapValues { json in json.stringValue }
                return InstancesBridge().deserialize(dict)
            }
        }

        return []
    }

    var accounts: [Account] {
        if let accounts = json["accounts"].array {
            return accounts.compactMap { accountJSON in
                let dict = accountJSON.dictionaryValue.mapValues { json in json.stringValue }
                return AccountsBridge().deserialize(dict)
            }
        }

        return []
    }

    func performImport() {
        if includePublicLocations {
            Defaults[.instancesManifest] = json["instancesManifest"].string ?? ""
            Defaults[.countryOfPublicInstances] = json["countryOfPublicInstances"].string ?? ""
        }

        instances.filter { includedInstancesIDs.contains($0.id) }.forEach { instance in
            _ = InstancesModel.shared.insert(id: instance.id, app: instance.app, name: instance.name, url: instance.apiURLString)
        }

        if let accounts = json["accounts"].array {
            for accountJSON in accounts {
                let dict = accountJSON.dictionaryValue.mapValues { json in json.stringValue }
                if let account = AccountsBridge().deserialize(dict),
                   includedAccountsIDs.contains(account.id)
                {
                    var password = account.password
                    if password?.isEmpty ?? true {
                        password = includedAccountsPasswords[account.id]
                    }
                    if let password,
                       !password.isEmpty,
                       let instanceID = account.instanceID,
                       let instance = InstancesModel.shared.find(instanceID) ?? InstancesModel.shared.findByURLString(account.urlString)
                    {
                        if !instance.accounts.contains(where: { instanceAccount in
                            let (username, _) = instanceAccount.credentials
                            return username == account.username
                        }) {
                            _ = AccountsModel.add(instance: instance, id: account.id, name: account.name, username: account.username, password: password)
                        }
                    }
                }
            }
        }
    }
}
