import SwiftUI

struct SettingsButtons: View {
    @ObservedObject private var accounts = AccountsModel.shared
    private var navigation = NavigationModel.shared

    var body: some View {
        Button(action: { navigation.presentingAccounts = true }) {
            Label(accounts.current?.description ?? "", image: accounts.app.rawValue.capitalized)
        }
        Button(action: { navigation.presentingSettings = true }) {
            Label("Settings", systemImage: "gearshape.2")
        }
    }
}

struct SettingsButtons_Previews: PreviewProvider {
    static var previews: some View {
        SettingsButtons()
    }
}
