import Defaults
import SwiftUI

struct WelcomeScreen: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<AccountsModel> private var accounts

    @Default(.accounts) private var allAccounts

    var body: some View {
        VStack {
            Spacer()

            Text("Welcome")
                .font(.largeTitle)
                .padding(.bottom, 10)

            if allAccounts.isEmpty {
                Text("To start, configure your Instances in Settings")
                    .foregroundColor(.secondary)
            } else {
                Text("To start, pick one of your accounts:")
                    .foregroundColor(.secondary)
                #if os(tvOS)
                    AccountSelectionView(showHeader: false)

                    Button {
                        dismiss()
                    } label: {
                        Text("Start")
                    }
                    .opacity(accounts.current.isNil ? 0 : 1)
                    .disabled(accounts.current.isNil)

                #else
                    AccountsMenuView()
                        .onChange(of: accounts.current) { _ in
                            dismiss()
                        }
                    #if os(macOS)
                        .frame(maxWidth: 280)
                    #endif
                #endif
            }

            Spacer()

            OpenSettingsButton()

            Spacer()
        }
        .interactiveDismissDisabled()
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 400)
        #endif
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen()
            .injectFixtureEnvironmentObjects()
    }
}
