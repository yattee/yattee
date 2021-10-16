import Defaults
import Foundation
import SwiftUI

struct AccountSelectionView: View {
    @EnvironmentObject<InstancesModel> private var instancesModel
    @EnvironmentObject<AccountsModel> private var accounts

    @Default(.instances) private var instances

    var body: some View {
        Section(header: Text("Current Account")) {
            Button(accountButtonTitle(account: accounts.account)) {
                if let account = nextAccount {
                    accounts.setAccount(account)
                }
            }
            .disabled(instances.isEmpty)
            .contextMenu {
                ForEach(accounts.all) { account in
                    Button(accountButtonTitle(account: account)) {
                        accounts.setAccount(account)
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        }
        .id(UUID())
    }

    private var nextAccount: Instance.Account? {
        accounts.all.next(after: accounts.account)
    }

    func accountButtonTitle(account: Instance.Account! = nil) -> String {
        guard account != nil else {
            return "Not selected"
        }

        return instances.count > 1 ? "\(account.description) — \(account.instance.shortDescription)" : account.description
    }
}
