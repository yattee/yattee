//
//  ExpandedPlayerSheet+Debug.swift
//  Yattee
//
//  Debug timer functionality for the expanded player sheet.
//

import SwiftUI

#if os(iOS) || os(macOS)

extension ExpandedPlayerSheet {
    // MARK: - Debug Timer

    /// Starts periodic updates of debug statistics from MPV backend.
    func startDebugUpdates() {
        stopDebugUpdates()
        guard let backend = playerService?.currentBackend as? MPVBackend else { return }
        debugStats = backend.getDebugStats()

        debugUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard let backend = self.playerService?.currentBackend as? MPVBackend else { return }
                self.debugStats = backend.getDebugStats()
            }
        }
    }

    /// Stops the debug statistics update timer.
    func stopDebugUpdates() {
        debugUpdateTimer?.invalidate()
        debugUpdateTimer = nil
    }
}

#endif
