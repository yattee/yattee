import Defaults
import SwiftUI

struct SignInRequiredView<Content: View>: View {
    let title: String
    let content: Content

    @EnvironmentObject<InvidiousAPI> private var api
    @Default(.instances) private var instances
    @EnvironmentObject<NavigationModel> private var navigation

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Group {
            if api.signedIn {
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
                    Text("You need to create an instance and accounts\nto access **\(title)** section")
                } else {
                    Text("You need to select an account\nto access **\(title)** section")
                }
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .font(.title3)
            .padding(.vertical)

            #if !os(tvOS)
                if instances.isEmpty {
                    openSettingsButton
                }
            #endif

            #if os(tvOS)
                openSettingsButton
            #endif
        }
    }

    var openSettingsButton: some View {
        Button(action: {
            #if os(macOS)
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            #else
                navigation.presentingSettings = true
            #endif
        }) {
            Text("Open Settings")
        }
        .buttonStyle(.borderedProminent)
    }
}

struct SignInRequiredView_Previews: PreviewProvider {
    static var previews: some View {
        SignInRequiredView(title: "Subscriptions") {
            Text("Only when signed in")
        }
        .environmentObject(InvidiousAPI())
    }
}
