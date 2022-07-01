import Defaults
import Siesta
import SwiftUI

struct WelcomeScreen: View {
    @Environment(\.presentationMode) private var presentationMode

    @EnvironmentObject<AccountsModel> private var accounts
    @State private var store = [ManifestedInstance]()

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()

            Text("Welcome to Yattee")
                .frame(maxWidth: .infinity)
                .font(.largeTitle)
                .padding(.bottom, 10)

            Text("Select location closest to you to get the best performance")
                .font(.subheadline)

            ScrollView {
                ForEach(store.map(\.country).sorted(), id: \.self) { country in
                    Button {
                        Defaults[.countryOfPublicInstances] = country
                        InstancesManifest.shared.setPublicAccount(country, accounts: accounts)

                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            if let flag = flag(country) {
                                Text(flag)
                            }
                            Text(country)
                            #if !os(tvOS)
                                .foregroundColor(.white)
                            #endif
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        #if os(tvOS)
                        .padding(8)
                        #else
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 4).foregroundColor(Color.accentColor))
                        .padding(.bottom, 2)
                        #endif
                    }
                    .buttonStyle(.plain)
                    #if os(tvOS)
                        .padding(.horizontal, 10)
                    #endif
                }
                .padding(.horizontal, 30)
            }

            Text("This information will not be collected and it will be saved only on your device. You can change it later in settings.")
                .font(.caption)
                .foregroundColor(.secondary)

            #if !os(tvOS)
                Spacer()

                OpenSettingsButton()
                    .frame(maxWidth: .infinity)

                Spacer()
            #endif
        }
        .onAppear {
            resource.load().onSuccess { response in
                if let instances: [ManifestedInstance] = response.typedContent() {
                    store = instances
                }
            }
        }
        .padding()
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 400)
        #elseif os(tvOS)
            .frame(maxWidth: 1000)
        #endif
    }

    func flag(_ country: String) -> String? {
        store.first { $0.country == country }?.flag
    }

    var resource: Resource {
        InstancesManifest.shared.instancesList
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen()
            .injectFixtureEnvironmentObjects()
    }
}
