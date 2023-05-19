import Social
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        openExtensionContextURLs()
    }

    private func openExtensionContextURLs() {
        for item in extensionContext?.inputItems as! [NSExtensionItem] {
            if let attachments = item.attachments {
                tryToOpenItemForUrlTypeIdentifier(attachments)
                tryToOpenItemForPlainTextTypeIdentifier(attachments)
            }
        }
    }

    private func tryToOpenItemForPlainTextTypeIdentifier(_ attachments: [NSItemProvider]) {
        for itemProvider in attachments {
            itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let url = (item as? String),
                   let absoluteURL = URL(string: url)?.absoluteURL
                {
                    if let url = URL(string: "yattee://\(absoluteURL.absoluteString)") {
                        self.open(url: url)
                    }

                    self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            }
        }
    }

    private func tryToOpenItemForUrlTypeIdentifier(_ attachments: [NSItemProvider]) {
        for itemProvider in attachments {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = (item as? NSURL), let absoluteURL = url.absoluteURL {
                    if let url = URL(string: "yattee://\(absoluteURL.absoluteString)") {
                        self.open(url: url)
                    }

                    self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
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
        openExtensionContextURLs()
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }
}
