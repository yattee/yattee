//
//  PlatformMenuPicker.swift
//  Yattee
//
//  A Picker wrapper that renders as a compact menu inside LabeledContent on tvOS,
//  and as a standard inline Picker on iOS/macOS. Use this for short option lists
//  in settings forms so tvOS shows a dropdown menu rather than pushing a sub-view.
//

import SwiftUI

struct PlatformMenuPicker<Selection: Hashable, Label: View, Content: View>: View {
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    var body: some View {
        #if os(tvOS)
        LabeledContent {
            Picker(selection: $selection, content: content) { EmptyView() }
                .pickerStyle(.menu)
                .labelsHidden()
        } label: {
            label()
        }
        #else
        Picker(selection: $selection, content: content, label: label)
        #endif
    }
}

extension PlatformMenuPicker where Label == Text {
    init(
        _ titleKey: String,
        selection: Binding<Selection>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._selection = selection
        self.content = content
        self.label = { Text(titleKey) }
    }
}
