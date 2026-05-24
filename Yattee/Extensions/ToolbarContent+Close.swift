//
//  ToolbarContent+Close.swift
//  Yattee
//
//  Shared sheet-dismiss toolbar item.
//

import SwiftUI

/// Standard sheet-dismiss toolbar item.
///
/// On macOS this renders a native text button (e.g. "Close"), which fits the desktop
/// convention. On iOS/tvOS it renders the compact icon-only xmark used by the rest of
/// the app's sheets.
///
/// Placement defaults to `.confirmationAction`; only the *label* changes per platform,
/// so it can be dropped into existing `.toolbar { }` blocks without changing layout.
@ToolbarContentBuilder
func sheetCloseToolbarItem(
    placement: ToolbarItemPlacement = .confirmationAction,
    titleKey: LocalizedStringResource = "common.close",
    identifier: String? = nil,
    action: @escaping () -> Void
) -> some ToolbarContent {
    ToolbarItem(placement: placement) {
        sheetCloseButton(titleKey: titleKey, identifier: identifier, action: action)
    }
}

@ViewBuilder
private func sheetCloseButton(
    titleKey: LocalizedStringResource,
    identifier: String?,
    action: @escaping () -> Void
) -> some View {
    let button = Button(role: .cancel, action: action) {
        #if os(macOS)
        Text(String(localized: titleKey))
        #else
        Label(String(localized: titleKey), systemImage: "xmark")
            .labelStyle(.iconOnly)
        #endif
    }

    if let identifier {
        button.accessibilityIdentifier(identifier)
    } else {
        button
    }
}
