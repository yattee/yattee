import SwiftUI

struct AccountSettingsView: View {
    let instance: Instance
    let account: Instance.Account
    @Binding var selectedAccount: Instance.Account?

    @State private var presentingRemovalConfirmationDialog = false

    @EnvironmentObject<InstancesModel> private var instances

    var body: some View {
        HStack {
            Text(account.description)
            Spacer()

            HStack {
                Button("Remove", role: .destructive) {
                    presentingRemovalConfirmationDialog = true
                }
                .confirmationDialog(
                    "Are you sure you want to remove \(account.description) account?",
                    isPresented: $presentingRemovalConfirmationDialog
                ) {
                    Button("Remove", role: .destructive) {
                        instances.removeAccount(instance: instance, account: account)
                    }
                }
                #if os(macOS)
                    .foregroundColor(.red)
                #endif
            }
            .opacity(account == selectedAccount ? 1 : 0)
        }
    }
}
