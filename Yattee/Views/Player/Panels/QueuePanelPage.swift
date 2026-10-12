//
//  QueuePanelPage.swift
//  Yattee
//
//  Details panel page hosting the shared queue list.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct QueuePanelPage: View {
    var settings: QueuePageSettings = QueuePageSettings()
    var bottomInset: CGFloat = 0

    var body: some View {
        QueueListView(
            showHistory: settings.effectiveShowHistory,
            showNowPlaying: settings.effectiveShowNowPlaying
        )
        .safeAreaPadding(.bottom, bottomInset)
        .panelListLeadingMargin()
    }
}

#endif
