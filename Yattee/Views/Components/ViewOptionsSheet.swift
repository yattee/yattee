//
//  ViewOptionsSheet.swift
//  Yattee
//
//  Reusable sheet for customizing video list display options.
//

import SwiftUI

/// A sheet for customizing video list display options.
///
/// Shows layout picker (list/grid), size options, and filter toggles.
/// Reusable across different views with their own storage bindings.
struct ViewOptionsSheet: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Binding var layout: VideoListLayout
    @Binding var rowStyle: VideoRowStyle
    @Binding var gridColumns: Int
    
    /// Optional binding for hide watched toggle (only shown if provided).
    var hideWatched: Binding<Bool>?
    
    /// Optional binding for channel strip size (only shown if provided).
    var channelStripSize: Binding<ChannelStripSize>?

    /// Maximum columns allowed based on current view width.
    var maxGridColumns: Int

    /// Effective columns clamped to valid range.
    private var effectiveColumns: Int {
        min(max(1, gridColumns), maxGridColumns)
    }

    var body: some View {
        #if os(tvOS)
        tvOSContent
        #else
        formContent
        #endif
    }

    #if os(tvOS)
    private var tvOSContent: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $layout) {
                        ForEach(VideoListLayout.allCases, id: \.self) { option in
                            Label(option.displayName, systemImage: option.systemImage)
                                .tag(option)
                        }
                    } label: {
                        Text("viewOptions.layout")
                    }
                    .pickerStyle(.segmented)

                    if layout == .list {
                        Picker("viewOptions.rowSize", selection: $rowStyle) {
                            Text("viewOptions.rowSize.compact").tag(VideoRowStyle.compact)
                            Text("viewOptions.rowSize.regular").tag(VideoRowStyle.regular)
                            Text("viewOptions.rowSize.large").tag(VideoRowStyle.large)
                        }
                    }

                    if layout == .grid {
                        Picker("viewOptions.columns.header", selection: $gridColumns) {
                            ForEach(1...maxGridColumns, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                    }

                    if let hideWatched = hideWatched {
                        Toggle("viewOptions.hideWatched", isOn: hideWatched)
                    }

                    if let channelStripSize = channelStripSize {
                        Picker("viewOptions.channelStrip", selection: channelStripSize) {
                            ForEach(ChannelStripSize.allCases, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
        }
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
    }
    #endif

    private var formContent: some View {
        Form {
            // Single section with all options
            Section {
                // Layout picker (segmented)
                Picker(selection: $layout) {
                    ForEach(VideoListLayout.allCases, id: \.self) { option in
                        Label(option.displayName, systemImage: option.systemImage)
                            .tag(option)
                    }
                } label: {
                    Text("viewOptions.layout")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                // List-specific options
                if layout == .list {
                    Picker("viewOptions.rowSize", selection: $rowStyle) {
                        Text("viewOptions.rowSize.compact").tag(VideoRowStyle.compact)
                        Text("viewOptions.rowSize.regular").tag(VideoRowStyle.regular)
                        Text("viewOptions.rowSize.large").tag(VideoRowStyle.large)
                    }
                }

                // Grid-specific options
                if layout == .grid {
                    #if os(tvOS)
                    Picker("viewOptions.columns.header", selection: $gridColumns) {
                        ForEach(1...maxGridColumns, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    #else
                    Stepper(
                        "viewOptions.columns \(effectiveColumns)",
                        value: $gridColumns,
                        in: 1...maxGridColumns
                    )
                    #endif
                }

                // Filters (optional)
                if let hideWatched = hideWatched {
                    Toggle("viewOptions.hideWatched", isOn: hideWatched)
                }

                // Channel Strip (subscriptions only)
                if let channelStripSize = channelStripSize {
                    Picker("viewOptions.channelStrip", selection: channelStripSize) {
                        ForEach(ChannelStripSize.allCases, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        #endif
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var layout: VideoListLayout = .grid
    @Previewable @State var rowStyle: VideoRowStyle = .regular
    @Previewable @State var gridColumns = 2
    @Previewable @State var hideWatched = false

    ViewOptionsSheet(
        layout: $layout,
        rowStyle: $rowStyle,
        gridColumns: $gridColumns,
        hideWatched: $hideWatched,
        channelStripSize: nil,
        maxGridColumns: 4
    )
}
