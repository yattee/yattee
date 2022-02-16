import Defaults
import SwiftUI

struct SignInRequiredView<Content: View>: View {
    let title: String
    let content: Content

    @EnvironmentObject<AccountsModel> private var accounts

    @Default(.instances) private var instances

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Group {
            if accounts.signedIn {
                content
            } else {
                prompt
            }
        }
        #if !os(tvOS)
        .navigationTitle(title)
        #endif
    }

    var prompt: some View {
        VStack(spacing: 30) {
            Text("Sign In Required")
                .font(.title2.bold())

            Group {
                if instances.isEmpty {
                    Text("You need to create an instance and accounts\nto access \(title) section")
                } else {
                    Text("You need to select an account\nto access \(title) section")
                }
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .font(.title3)
            .padding(.vertical)

            #if !os(tvOS)
                if instances.isEmpty {
                    OpenSettingsButton()
                }
            #endif

            #if os(tvOS)
                OpenSettingsButton()
            #endif
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
    }
}

struct SignInRequiredView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserPlayerControls {
            SignInRequiredView(title: "Subscriptions") {
                Text("Only when signed in")
            }
        }
        .environmentObject(PlayerModel())
        .environmentObject(InvidiousAPI())
    }
}
