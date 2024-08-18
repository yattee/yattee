import UIKit

extension UIViewController {
    @objc var swizzle_prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    public class func swizzleHomeIndicatorProperty() {
        swizzle(
            origSelector: #selector(getter: UIViewController.prefersHomeIndicatorAutoHidden),
            withSelector: #selector(getter: UIViewController.swizzle_prefersHomeIndicatorAutoHidden),
            forClass: UIViewController.self
        )
    }
}
