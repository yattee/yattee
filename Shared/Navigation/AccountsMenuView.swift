import Defaults
import SwiftUI

struct AccountsMenuView: View {
    @EnvironmentObject<AccountsModel> private var model

    @Default(.accounts) private var accounts
    @Default(.instances) private var instances
    @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername

    var body: some View {
        Menu {
            ForEach(allAccounts, id: \.id) { account in
                Button {
                    model.setCurrent(account)
                } label: {
                    HStack {
                        Text(accountButtonTitle(account: account))

                        Spacer()

                        if model.current == account {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "person.crop.circle")
                if accountPickerDisplaysUsername {
                    label
                        .labelStyle(.titleOnly)
                }
            }
        }
        .disabled(instances.isEmpty)
        .transaction { t in t.animation = .none }
    }

    private var label: some View {
        Label(model.current?.description ?? "Select Account", systemImage: "person.crop.circle")
    }

    private var allAccounts: [Account] {
        accounts + instances.map(\.anonymousAccount)
    }

    private func accountButtonTitle(account: Account) -> String {
        instances.count > 1 ? "\(account.description) — \(account.instance.description)" : account.description
    }
}
