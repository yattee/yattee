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
    var bottomInset: CGFloat = 0

    var body: some View {
        QueueListView()
            .safeAreaPadding(.bottom, bottomInset)
    }
}

#endif
