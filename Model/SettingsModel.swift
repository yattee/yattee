import Foundation
import SwiftUI

final class SettingsModel: ObservableObject {
    static var shared = SettingsModel()

    @Published var presentingAlert = false
    @Published var alert = Alert(title: Text("Error"))

    @Published var presentingSettingsImportSheet = false
    @Published var settingsImportURL: URL?

    func presentAlert(title: String, message: String? = nil) {
        let message = message.isNil ? nil : Text(message!)
        alert = Alert(title: Text(title), message: message)
        presentingAlert = true
    }

    func presentAlert(_ alert: Alert) {
        self.alert = alert
        presentingAlert = true
    }

    func presentSettingsImportSheet(_ url: URL) {
        settingsImportURL = url
        presentingSettingsImportSheet = true
    }
}
