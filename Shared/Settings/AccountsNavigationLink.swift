import SwiftUI

struct AccountsNavigationLink: View {
    @EnvironmentObject<AccountsModel> private var accounts
    var instance: Instance

    var body: some View {
        NavigationLink(instance.longDescription) {
            InstanceSettings(instanceID: instance.id)
        }
        .buttonStyle(.plain)
        .contextMenu {
            removeInstanceButton(instance)
        }
    }

    private func removeInstanceButton(_ instance: Instance) -> some View {
        if #available(iOS 15.0, *) {
            return Button("Remove", role: .destructive) { removeAction(instance) }
        } else {
            return Button("Remove") { removeAction(instance) }
        }
    }

    private func removeAction(_ instance: Instance) {
        if accounts.current?.instance == instance {
            accounts.setCurrent(nil)
        }
        InstancesModel.remove(instance)
    }
}
