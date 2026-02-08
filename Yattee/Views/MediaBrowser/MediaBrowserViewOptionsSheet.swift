//
//  MediaBrowserViewOptionsSheet.swift
//  Yattee
//
//  Sheet for customizing media browser view options.
//

import SwiftUI

struct MediaBrowserViewOptionsSheet: View {
    @Binding var sortOrder: MediaBrowserSortOrder
    @Binding var sortAscending: Bool
    @Binding var showOnlyPlayable: Bool
    let sourceType: MediaSourceType

    @Environment(\.dismiss) private var dismiss

    private var availableSortOptions: [MediaBrowserSortOrder] {
        MediaBrowserSortOrder.availableOptions(for: sourceType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("mediaBrowser.viewOptions.sortBy", selection: $sortOrder) {
                        ForEach(availableSortOptions) { order in
                            Label(order.displayName, systemImage: order.systemImage)
                                .tag(order)
                        }
                    }
                } header: {
                    Text("mediaBrowser.viewOptions.sortBy")
                }

                Section {
                    Picker("mediaBrowser.viewOptions.order", selection: $sortAscending) {
                        Label(String(localized: "mediaBrowser.viewOptions.ascending"), systemImage: "arrow.up")
                            .tag(true)
                        Label(String(localized: "mediaBrowser.viewOptions.descending"), systemImage: "arrow.down")
                            .tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                } header: {
                    Text("mediaBrowser.viewOptions.order")
                }

                Section {
                    Toggle("mediaBrowser.viewOptions.showOnlyPlayable", isOn: $showOnlyPlayable)
                } header: {
                    Text("mediaBrowser.viewOptions.filters")
                }
            }
            .navigationTitle("mediaBrowser.viewOptions.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            // Reset sort order if current selection is not available for this source type
            if !availableSortOptions.contains(sortOrder) {
                sortOrder = .name
            }
        }
    }
}

// MARK: - Preview

#Preview("Local Folder") {
    @Previewable @State var sortOrder: MediaBrowserSortOrder = .name
    @Previewable @State var sortAscending = true
    @Previewable @State var showOnlyPlayable = false

    MediaBrowserViewOptionsSheet(
        sortOrder: $sortOrder,
        sortAscending: $sortAscending,
        showOnlyPlayable: $showOnlyPlayable,
        sourceType: .localFolder
    )
}

#Preview("WebDAV") {
    @Previewable @State var sortOrder: MediaBrowserSortOrder = .name
    @Previewable @State var sortAscending = true
    @Previewable @State var showOnlyPlayable = false

    MediaBrowserViewOptionsSheet(
        sortOrder: $sortOrder,
        sortAscending: $sortAscending,
        showOnlyPlayable: $showOnlyPlayable,
        sourceType: .webdav
    )
}
