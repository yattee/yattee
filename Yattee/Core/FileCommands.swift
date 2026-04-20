//
//  FileCommands.swift
//  Yattee
//
//  Menu bar commands for file operations.
//

import SwiftUI

#if !os(tvOS)
/// File-related menu bar commands.
struct FileCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "menu.file.openLink")) {
                NotificationCenter.default.post(name: .showOpenLinkSheet, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
        #if os(macOS)
        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "menu.app.settings")) {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
        #endif
    }
}
#endif
