import Defaults
import SwiftUI

struct UpdatesSettings: View {
    @EnvironmentObject<UpdaterModel> private var updater

    @State private var automaticallyChecksForUpdates = false
    @Default(.enableBetaChannel) private var enableBetaChannel

    var body: some View {
        Section(header: SettingsHeader(text: "Updates")) {
            Toggle("Check automatically", isOn: $automaticallyChecksForUpdates)
            Toggle("Enable beta channel", isOn: $enableBetaChannel)
        }
        .onAppear {
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        }
        .onChange(of: automaticallyChecksForUpdates) { _ in
            updater.setAutomaticallyChecksForUpdates(automaticallyChecksForUpdates)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Spacer()

        Text("Yattee \(YatteeApp.version) (build \(YatteeApp.build))")
            .foregroundColor(.secondary)

        CheckForUpdatesView()
    }
}

struct UpdatesSettings_Previews: PreviewProvider {
    static var previews: some View {
        UpdatesSettings()
            .injectFixtureEnvironmentObjects()
    }
}
