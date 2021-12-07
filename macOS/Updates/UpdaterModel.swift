import Defaults
import Sparkle
import SwiftUI

final class UpdaterModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = UpdaterDelegate()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController.updater.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = value
    }
}

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @Default(.enableBetaChannel) private var enableBetaChannel

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        Set(enableBetaChannel ? ["beta"] : [])
    }
}
