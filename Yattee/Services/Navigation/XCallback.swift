//
//  XCallback.swift
//  Yattee
//
//  x-callback-url support (https://x-callback-url.com):
//
//    yattee://x-callback-url/{verb}?{action parameters}
//        &x-success={url}&x-error={url}&x-cancel={url}&x-source={app name}
//
//  `{verb}` is any `LinkAction` host (`play`, `queue`, `player/pause`, …).
//  When the action finishes Yattee opens one of the callbacks:
//    x-success  with the action's values appended (videoID, title, …)
//    x-error    with errorCode and errorMessage appended
//    x-cancel   when the user declined a confirmation
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct XCallback: Equatable {
    static let host = "x-callback-url"

    let success: URL?
    let error: URL?
    let cancel: URL?
    /// The calling app's name, as it chose to send it.
    let source: String?

    /// Callbacks of an x-callback-url request, or nil for any other URL.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "yattee", url.host?.lowercased() == Self.host else { return nil }
        let query = LinkActionParser.queryParameters(of: url)
        success = query["x-success"].flatMap(Self.callbackURL)
        error = query["x-error"].flatMap(Self.callbackURL)
        cancel = query["x-cancel"].flatMap(Self.callbackURL)
        source = query["x-source"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The action an x-callback-url request asks for, written as the plain
    /// action link: yattee://x-callback-url/player/seek?t=9 → yattee://player/seek?t=9.
    static func actionURL(from url: URL) -> URL? {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        let absolute = url.absoluteString
        // Keep the query exactly as sent: it may hold an unencoded link
        let query = absolute.firstIndex(of: "?").map { String(absolute[$0...]) } ?? ""
        return URL(string: "yattee://\(path)\(query)")
    }

    /// The callback to open for a result, with the result's values appended.
    func url(for result: LinkActionResult) -> URL? {
        switch result {
        case .success(let values):
            return success.map { Self.appending(values, to: $0) }
        case .failure(let code, let message):
            return error.map { Self.appending(["errorCode": code, "errorMessage": message], to: $0) }
        case .cancelled:
            // Callers that don't handle cancel still learn the action didn't run
            if let cancel { return cancel }
            return error.map { Self.appending(["errorCode": "cancelled", "errorMessage": "Cancelled"], to: $0) }
        }
    }

    /// Opens the callback for a result, if the caller gave one.
    @MainActor
    func open(for result: LinkActionResult) {
        guard let url = url(for: result) else { return }
        LoggingService.shared.info("x-callback-url: returning to \(url.scheme ?? "?")://", category: .general)
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: - Helpers

    /// Callbacks go back to an app, never to a local file or a script.
    private static func callbackURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              !["file", "javascript", "data"].contains(scheme) else {
            return nil
        }
        return url
    }

    /// Appends parameters, escaping everything a query value can't hold as-is
    /// (`URLComponents` leaves `&`, `=` and `+` alone).
    static func appending(_ values: [String: String], to url: URL) -> URL {
        guard !values.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let added = values.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        components.percentEncodedQuery = ([components.percentEncodedQuery].compactMap { $0 }.filter { !$0.isEmpty } + added)
            .joined(separator: "&")
        return components.url ?? url
    }
}
