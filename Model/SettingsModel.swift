import Foundation
import SwiftUI

class SettingsModel: ObservableObject {
    @Published var presentingAlert = false
    @Published var alert = Alert(title: Text("Error"))

    func presentAlert(title: String, message: String? = nil) {
        let message = message.isNil ? nil : Text(message!)
        alert = Alert(title: Text(title), message: message)
        presentingAlert = true
    }

    func presentAlert(_ alert: Alert) {
        self.alert = alert
        presentingAlert = true
    }
}
