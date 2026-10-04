//
//  View+PlatformSheet.swift
//  Yattee
//
//  A modal that is a full-screen cover on tvOS and a sheet elsewhere, for
//  forms (sign-in) that need the whole screen on tvOS.
//

import SwiftUI

extension View {
    func platformSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
