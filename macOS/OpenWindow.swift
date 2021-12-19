import AppKit
import Foundation

enum OpenWindow: String, CaseIterable {
    case player, main

    var window: NSWindow? {
        // this is not solid but works as long as there is only two windows in the app
        // needs to be changed in case we ever have more windows to handle

        switch self {
        case .player:
            return NSApplication.shared.windows.last
        case .main:
            return NSApplication.shared.windows.first
        }
    }

    func focus() {
        window?.makeKeyAndOrderFront(self)
    }

    var location: String {
        switch self {
        case .player:
            return rawValue
        case .main:
            return ""
        }
    }

    func open() {
        switch self {
        case .player:
            NSWorkspace.shared.open(URL(string: "yattee://\(location)")!)
        case .main:
            Self.main.focus()
        }
    }
}
