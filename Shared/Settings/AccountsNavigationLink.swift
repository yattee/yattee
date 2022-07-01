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

            #if os(tvOS)
                Button("Cancel", role: .cancel) {}
            #endif
        }
    }

    private func removeInstanceButton(_ instance: Instance) -> some View {
        Button {
            removeAction(instance)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func removeAction(_ instance: Instance) {
        if accounts.current?.instance == instance {
            accounts.setCurrent(nil)
        }
        InstancesModel.remove(instance)
    }
}
