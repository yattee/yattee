//
//  ShareViewController.swift
//  YatteeShareExtension
//
//  Handles shared URLs and opens them in Yattee.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                // Try to get URL first
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.openInYattee(url: url)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }

                // Try plain text (might contain a URL)
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            if let text = item as? String, let url = self?.extractURL(from: text) {
                                self?.openInYattee(url: url)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }
            }
        }

        close()
    }

    private func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           url.scheme == "http" || url.scheme == "https" {
            return url
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, options: [], range: range),
           let url = match.url {
            return url
        }

        return nil
    }

    private func openInYattee(url: URL) {
        guard let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let yatteeURL = URL(string: "yattee://open?url=\(encodedURL)") else {
            close()
            return
        }

        openURLViaApplication(yatteeURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.close()
        }
    }

    private func openURLViaApplication(_ url: URL) {
        let sharedSelector = NSSelectorFromString("sharedApplication")

        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type,
              appClass.responds(to: sharedSelector),
              let shared = appClass.perform(sharedSelector)?.takeUnretainedValue() else {
            return
        }

        typealias OpenURLMethod = @convention(c) (AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?) -> Void

        let openSelector = NSSelectorFromString("openURL:options:completionHandler:")
        guard shared.responds(to: openSelector) else { return }

        let methodIMP = shared.method(for: openSelector)
        let method = unsafeBitCast(methodIMP, to: OpenURLMethod.self)
        method(shared, openSelector, url, [:], nil)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
