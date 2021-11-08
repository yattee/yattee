import Defaults
import SwiftUI

struct InstancesSettings: View {
    @Default(.instances) private var instances

    @EnvironmentObject<AccountsModel> private var accounts

    @State private var selectedInstanceID: Instance.ID?
    @State private var selectedAccount: Account?

    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    var body: some View {
        Group {
            Section(header: SettingsHeader(text: "Instances")) {
                ForEach(instances) { instance in
                    Group {
                        NavigationLink(instance.longDescription) {
                            AccountsSettings(instanceID: instance.id)
                        }
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        removeInstanceButton(instance)
                    }
                    .buttonStyle(.plain)
                    #else
                    .contextMenu {
                        removeInstanceButton(instance)
                    }
                    #endif
                }

                addInstanceButton
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
        .sheet(isPresented: $presentingInstanceForm) {
            InstanceForm(savedInstanceID: $savedFormInstanceID)
        }
    }

    private var addInstanceButton: some View {
        Button("Add Instance...") {
            presentingInstanceForm = true
        }
    }

    private func removeInstanceButton(_ instance: Instance) -> some View {
        Button("Remove", role: .destructive) {
            if accounts.current?.instance == instance {
                accounts.setCurrent(nil)
            }
            InstancesModel.remove(instance)
        }
    }
}

struct InstancesSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            InstancesSettings()
        }
        .frame(width: 400, height: 270)
    }
}
