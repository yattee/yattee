import Defaults
import SwiftUI

struct WelcomeScreen: View {
    @Environment(\.presentationMode) private var presentationMode

    @EnvironmentObject<AccountsModel> private var accounts

    @Default(.accounts) private var allAccounts

    var body: some View {
        let welcomeScreen = VStack {
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
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Start")
                    }
                    .opacity(accounts.current.isNil ? 0 : 1)
                    .disabled(accounts.current.isNil)

                #else
                    AccountsMenuView()
                        .onChange(of: accounts.current) { _ in
                            presentationMode.wrappedValue.dismiss()
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
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif

        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            welcomeScreen
                .interactiveDismissDisabled()
        } else {
            welcomeScreen
        }
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen()
            .injectFixtureEnvironmentObjects()
    }
}
