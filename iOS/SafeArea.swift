import Foundation
import UIKit

struct SafeArea {
    static var insets: UIEdgeInsets {
        let keyWindow = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }

        return keyWindow?.safeAreaInsets ?? .init()
    }
}
