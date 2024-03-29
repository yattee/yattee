import SwiftUI

struct SettingsButtons: View {
    @ObservedObject private var accounts = AccountsModel.shared
    private var navigation = NavigationModel.shared

    var body: some View {
        Button(action: { navigation.presentingAccounts = true }) {
            if let account = accounts.current {
                Label(account.description, image: account.app?.rawValue.capitalized ?? "")
            } else {
                Label("Signed Out", systemImage: "xmark")
            }
        }
        Button(action: { navigation.presentingSettings = true }) {
            Label("Settings", systemImage: "gearshape.2")
        }
    }
}

struct SettingsButtons_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            SettingsButtons()
        }
    }
}
