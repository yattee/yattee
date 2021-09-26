import Defaults
import SwiftUI

struct AccountSettingsView: View {
    let account: Instance.Account
    @Binding var selectedAccount: Instance.Account?

    @State private var presentingRemovalConfirmationDialog = false

    @EnvironmentObject<InstancesModel> private var instances

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                Text(account.description)
                if instances.defaultAccount == account {
                    Text("— default")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack {
                if instances.defaultAccount != account {
                    Button("Make default", action: makeDefault)
                } else {
                    Button("Reset default", action: resetDefault)
                }
                Button("Remove", role: .destructive) {
                    presentingRemovalConfirmationDialog = true
                }
                .confirmationDialog(
                    "Are you sure you want to remove \(account.description) account?",
                    isPresented: $presentingRemovalConfirmationDialog
                ) {
                    Button("Remove", role: .destructive) {
                        instances.removeAccount(account)
                    }
                }
                #if os(macOS)
                    .foregroundColor(.red)
                #endif
            }
            .opacity(account == selectedAccount ? 1 : 0)
        }
    }

    private func makeDefault() {
        instances.setDefaultAccount(account)
    }

    private func resetDefault() {
        instances.resetDefaultAccount()
    }
}
