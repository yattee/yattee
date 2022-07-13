import Defaults
import Foundation
import SwiftUI

struct AccountSelectionView: View {
    var showHeader = true

    @EnvironmentObject<AccountsModel> private var accountsModel

    @Default(.accounts) private var accounts
    @Default(.instances) private var instances

    var body: some View {
        Section(header: Text(showHeader ? "Current Location" : "")) {
            Button(accountButtonTitle(account: accountsModel.current)) {
                if let account = nextAccount {
                    accountsModel.setCurrent(account)
                }
            }
            .disabled(instances.isEmpty && Defaults[.countryOfPublicInstances].isNil)
            .contextMenu {
                ForEach(allAccounts) { account in
                    Button(accountButtonTitle(account: account)) {
                        accountsModel.setCurrent(account)
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        }
        .id(UUID())
    }

    var allAccounts: [Account] {
        accounts + instances.map(\.anonymousAccount) + [accountsModel.publicAccount].compactMap { $0 }
    }

    private var nextAccount: Account? {
        allAccounts.next(after: accountsModel.current)
    }

    func accountButtonTitle(account: Account! = nil) -> String {
        guard account != nil else {
            return "Not selected"
        }

        return account.isPublic ? account.description : "\(account.description) — \(account.instance.shortDescription)"
    }
}
