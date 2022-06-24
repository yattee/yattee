import AppKit
import Foundation
import SwiftUI

enum Windows: String, CaseIterable {
    case player, main

    static var mainWindow: NSWindow?
    static var playerWindow: NSWindow?

    weak var window: NSWindow? {
        switch self {
        case .player:
            return Self.playerWindow
        case .main:
            return Self.mainWindow
        }
    }

    var isOpen: Bool {
        !window.isNil
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
            if let window = Self.playerWindow {
                window.makeKeyAndOrderFront(self)
            } else {
                NSWorkspace.shared.open(URL(string: "yattee://\(location)")!)
            }
        case .main:
            Self.main.focus()
        }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }
}

struct HostingWindowFinder: NSViewRepresentable {
    var callback: (NSWindow?) -> Void

    func makeNSView(context _: Self.Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            self.callback(view?.window)
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
