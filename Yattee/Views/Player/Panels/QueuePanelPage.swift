//
//  QueuePanelPage.swift
//  Yattee
//
//  Details panel page hosting the shared queue list.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct QueuePanelPage: View {
    let context: PanelPageContext
    var settings: QueuePageSettings = QueuePageSettings()
    var bottomInset: CGFloat = 0

    var body: some View {
        QueueListView(showHistory: settings.effectiveShowHistory)
            .safeAreaPadding(.bottom, bottomInset)
    }
}

#endif
