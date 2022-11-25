import Social
import UIKit

final class ShareViewController: SLComposeServiceViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        openExtensionContextURLs()

        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func openExtensionContextURLs() {
        for item in extensionContext?.inputItems as! [NSExtensionItem] {
            if let attachments = item.attachments {
                tryToOpenItemForPlainTextTypeIdentifier(attachments)
                tryToOpenItemForUrlTypeIdentifier(attachments)
            }
        }
    }

    private func tryToOpenItemForPlainTextTypeIdentifier(_ attachments: [NSItemProvider]) {
        for itemProvider in attachments where itemProvider.hasItemConformingToTypeIdentifier("public.plain-text") {
            itemProvider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
                if let url = (item as? String),
                   let absoluteURL = URL(string: url)?.absoluteURL
                {
                    URLBookmarkModel.shared.saveBookmark(absoluteURL)
                    if let url = URL(string: "yattee://\(absoluteURL.absoluteString)") {
                        self.open(url: url)
                    }
                }

                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    private func tryToOpenItemForUrlTypeIdentifier(_ attachments: [NSItemProvider]) {
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
        openExtensionContextURLs()
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }
}
