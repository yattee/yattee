import Defaults
import SwiftUI

struct AccountsMenuView: View {
    @EnvironmentObject<InstancesModel> private var instancesModel
    @EnvironmentObject<InvidiousAPI> private var api

    @Default(.instances) private var instances

    var body: some View {
        Menu {
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
        } label: {
            Label(api.account?.name ?? "Accounts", systemImage: "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .disabled(instances.isEmpty)
        .transaction { t in t.animation = .none }
    }

    func accountButtonTitle(instance: Instance, account: Instance.Account) -> String {
        instances.count > 1 ? "\(account.description) — \(instance.shortDescription)" : account.description
    }
}
