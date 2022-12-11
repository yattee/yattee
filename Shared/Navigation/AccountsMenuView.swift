import Defaults
import SwiftUI

struct AccountsMenuView: View {
    @ObservedObject private var model = AccountsModel.shared
    private var navigation = NavigationModel.shared

    @Default(.accounts) private var accounts
    @Default(.instances) private var instances
    @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername
    @Default(.accountPickerDisplaysAnonymousAccounts) private var accountPickerDisplaysAnonymousAccounts

    @ViewBuilder var body: some View {
        if !instances.isEmpty {
            Button {
                navigation.presentingAccounts = true
            } label: {
                HStack {
                    if !accountPickerDisplaysUsername || !(model.current?.isPublic ?? true) {
                        Image(systemName: "globe")
                    }

                    if accountPickerDisplaysUsername {
                        label
                            .labelStyle(.titleOnly)
                    }
                }
            }
            .transaction { t in t.animation = .none }
        }
    }

    private var label: some View {
        Label(model.current?.description ?? "Select Account", systemImage: "globe")
    }
}
