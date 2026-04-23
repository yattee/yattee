//
//  Notifications.swift
//  Yattee
//
//  App-wide notification names.
//

import Foundation

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
    static let showOpenLinkSheet = Notification.Name("showOpenLinkSheet")
    static let openDescriptionLink = Notification.Name("openDescriptionLink")
    /// Posted when a URL shortener (bit.ly, etc.) has been resolved to an
    /// ambiguous destination — the app isn't certain it can play it, so the
    /// user is prompted whether to try opening it in Yattee or in the browser.
    /// `object` is the resolved `URL`.
    static let promptResolvedShortLink = Notification.Name("promptResolvedShortLink")
    /// Posted when a tapped link is not confidently a video (no YouTube /
    /// PeerTube / direct-media match) but could potentially be extracted via
    /// the Yattee server / yt-dlp. User is prompted whether to try extracting
    /// or open it in the system browser instead.
    /// `object` is the candidate `URL`.
    static let promptAmbiguousExternalLink = Notification.Name("promptAmbiguousExternalLink")
}
