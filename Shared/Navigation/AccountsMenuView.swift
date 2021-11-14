import Defaults
import SwiftUI

struct AccountsMenuView: View {
    @EnvironmentObject<AccountsModel> private var model

    @Default(.accounts) private var accounts
    @Default(.instances) private var instances

    var body: some View {
        Menu {
            ForEach(allAccounts, id: \.id) { account in
                Button(accountButtonTitle(account: account)) {
                    model.setCurrent(account)
                }
            }
        } label: {
            Label(model.current?.description ?? "Select Account", systemImage: "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .disabled(instances.isEmpty)
        .transaction { t in t.animation = .none }
    }

    private var allAccounts: [Account] {
        accounts + instances.map(\.anonymousAccount)
    }

    private func accountButtonTitle(account: Account) -> String {
        instances.count > 1 ? "\(account.description) — \(account.instance.description)" : account.description
    }
}
