import Social
import UIKit

final class ShareViewController: SLComposeServiceViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        for item in extensionContext!.inputItems as! [NSExtensionItem] {
            if let attachments = item.attachments {
                for itemProvider in attachments where itemProvider.hasItemConformingToTypeIdentifier("public.url") {
                    itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
                        if let url = (item as? NSURL), let absoluteURL = url.absoluteURL {
                            URLBookmarkModel.shared.saveBookmark(absoluteURL)
                            if let url = URL(string: "yattee://\(absoluteURL.absoluteString)") {
                                self.open(url: url)
                            }
                        }
                        self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                }
            }
        }
    }

    private func open(url: URL) {
        var responder: UIResponder? = self as UIResponder
        let selector = #selector(openURL(_:))

        while responder != nil {
            if responder!.responds(to: selector), responder != self {
                responder!.perform(selector, with: url)

                return
            }

            responder = responder?.next
        }
    }

    @objc
    private func openURL(_: URL) {}

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }
}
