import Defaults
import SwiftyJSON

final class LocationsSettingsGroupExporter: SettingsGroupExporter {
    var includePublicInstances = true
    var includeInstances = true
    var includeAccounts = true
    var includeAccountsUnencryptedPasswords = false

    init(includePublicInstances: Bool = true, includeInstances: Bool = true, includeAccounts: Bool = true, includeAccountsUnencryptedPasswords: Bool = false) {
        self.includePublicInstances = includePublicInstances
        self.includeInstances = includeInstances
        self.includeAccounts = includeAccounts
        self.includeAccountsUnencryptedPasswords = includeAccountsUnencryptedPasswords
    }

    override var globalJSON: JSON {
        var json = JSON()

        if includePublicInstances {
            json["instancesManifest"].string = Defaults[.instancesManifest]
            json["countryOfPublicInstances"].string = Defaults[.countryOfPublicInstances] ?? ""
        }

        if includeInstances {
            json["instances"].arrayObject = Defaults[.instances].compactMap { instanceJSON($0) }
        }

        if includeAccounts {
            json["accounts"].arrayObject = Defaults[.accounts].compactMap { account in
                var account = account
                let (username, password) = AccountsModel.getCredentials(account)
                account.username = username ?? ""
                if includeAccountsUnencryptedPasswords {
                    account.password = password ?? ""
                }

                return accountJSON(account).dictionaryObject
            }
        }

        return json
    }

    private func instanceJSON(_ instance: Instance) -> JSON {
        var json = JSON()
        json.dictionaryObject = InstancesBridge().serialize(instance)
        return json
    }

    private func accountJSON(_ account: Account) -> JSON {
        var json = JSON()
        json.dictionaryObject = AccountsBridge().serialize(account)
        return json
    }
}
