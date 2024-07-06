import Foundation
import SwiftUI

final class ImportSettingsSheetViewModel: ObservableObject {
    static let shared = ImportSettingsSheetViewModel()

    @Published var selectedInstances = Set<Instance.ID>()
    @Published var selectedAccounts = Set<Account.ID>()

    @Published var importableAccounts = Set<Account.ID>()
    @Published var importableAccountsPasswords = [Account.ID: String]()

    func toggleInstance(_ instance: Instance, accounts: [Account]) {
        if selectedInstances.contains(instance.id) {
            selectedInstances.remove(instance.id)
        } else {
            guard isImportable(instance) else { return }
            selectedInstances.insert(instance.id)
        }

        removeNonImportableFromSelectedAccounts(accounts: accounts)
    }

    func toggleAccount(_ account: Account, accounts: [Account]) {
        if selectedAccounts.contains(account.id) {
            selectedAccounts.remove(account.id)
        } else {
            guard isImportable(account.id, accounts: accounts) else { return }
            selectedAccounts.insert(account.id)
        }
    }

    func isSelectedForImport(_ account: Account) -> Bool {
        importableAccounts.contains(account.id) && selectedAccounts.contains(account.id)
    }

    func isImportable(_ accountID: Account.ID, accounts: [Account]) -> Bool {
        guard let account = accounts.first(where: { $0.id == accountID }),
              let instanceID = account.instanceID,
              AccountsModel.shared.find(accountID) == nil
        else { return false }

        return ((account.password != nil && !account.password!.isEmpty) ||
            importableAccounts.contains(account.id)) && (
            (InstancesModel.shared.find(instanceID) != nil || InstancesModel.shared.findByURLString(account.urlString) != nil) ||
                selectedInstances.contains(instanceID)
        )
    }

    func isImportable(_ instance: Instance) -> Bool {
        !isInstanceAlreadyAdded(instance)
    }

    func isInstanceAlreadyAdded(_ instance: Instance) -> Bool {
        InstancesModel.shared.find(instance.id) != nil || InstancesModel.shared.findByURLString(instance.apiURLString) != nil
    }

    func removeNonImportableFromSelectedAccounts(accounts: [Account]) {
        selectedAccounts = Set(selectedAccounts.filter { isImportable($0, accounts: accounts) })
    }

    func reset() {
        selectedAccounts = []
        selectedInstances = []
        importableAccounts = []
    }

    func reset(_ importer: LocationsSettingsGroupImporter? = nil) {
        reset()

        guard let importer else { return }

        selectedInstances = Set(importer.instances.filter { isImportable($0) }.map(\.id))
        importableAccounts = Set(importer.accounts.filter { isImportable($0.id, accounts: importer.accounts) }.map(\.id))
        selectedAccounts = importableAccounts
    }
}
