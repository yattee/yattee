import Defaults
import SwiftUI

struct AccountsMenuView: View {
    @EnvironmentObject<AccountsModel> private var model

    @Default(.instances) private var instances

    var body: some View {
        Menu {
            ForEach(model.all, id: \.id) { account in
                Button(accountButtonTitle(account: account)) {
                    model.setAccount(account)
                }
            }
        } label: {
            Label(model.account?.name ?? "Select Account", systemImage: "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .disabled(instances.isEmpty)
        .transaction { t in t.animation = .none }
    }

    func accountButtonTitle(account: Instance.Account) -> String {
        instances.count > 1 ? "\(account.description) — \(account.instance.description)" : account.description
    }
}
