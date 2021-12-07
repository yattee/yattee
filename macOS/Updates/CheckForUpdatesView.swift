import SwiftUI

struct CheckForUpdatesView: View {
    @EnvironmentObject<UpdaterModel> private var updater

    var body: some View {
        Button("Check For Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}
