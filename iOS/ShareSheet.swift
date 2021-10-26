import Foundation
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    typealias Callback = (_ activityType: UIActivity.ActivityType?,
                          _ completed: Bool,
                          _ returnedItems: [Any]?,
                          _ error: Error?) -> Void

    let activityItems: [Any]
    let applicationActivities = [UIActivity]()
    let excludedActivityTypes = [UIActivity.ActivityType]()
    let callback: Callback? = nil

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )

        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = callback

        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
