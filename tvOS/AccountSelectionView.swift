import Defaults
import Foundation
import SwiftUI

struct AccountSelectionView: View {
    @EnvironmentObject<InstancesModel> private var instancesModel
    @EnvironmentObject<InvidiousAPI> private var api

    @Default(.accounts) private var accounts
    @Default(.instances) private var instances

    var body: some View {
        Section(header: Text("Current Account")) {
            Button(api.account?.name ?? "Not selected") {
                if let account = nextAccount {
                    api.setAccount(account)
                }
            }
            .disabled(nextAccount == nil)
            .contextMenu {
                ForEach(instances) { instance in
                    Button(accountButtonTitle(instance: instance, account: instance.anonymousAccount)) {
                        api.setAccount(instance.anonymousAccount)
                    }

                    ForEach(instancesModel.accounts(instance.id)) { account in
                        Button(accountButtonTitle(instance: instance, account: account)) {
                            api.setAccount(account)
                        }
                    }
                }
            }
        }
    }

    private var nextAccount: Instance.Account? {
        guard api.account != nil else {
            return accounts.first
        }

        return accounts.next(after: api.account!)
    }

    func accountButtonTitle(instance: Instance, account: Instance.Account) -> String {
        instances.count > 1 ? "\(account.description) — \(instance.shortDescription)" : account.description
    }
}
