//
//  LogViewerView.swift
//  Yattee
//
//  In-app log viewer for debugging.
//

import SwiftUI

struct LogViewerView: View {
    @State private var loggingService = LoggingService.shared
    @State private var showingFilters = false
    @State private var showingExportSheet = false
    @State private var selectedEntry: LogEntry?

    #if os(tvOS)
    @State private var logExportServer = LogExportHTTPServer()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Log list
            logList
        }
        .navigationTitle(String(localized: "settings.advanced.logs.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingFilters = true
                    } label: {
                        Label(String(localized: "settings.advanced.logs.filter"), systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        showingExportSheet = true
                    } label: {
                        Label(String(localized: "settings.advanced.logs.export"), systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        loggingService.clearLogs()
                    } label: {
                        Label(String(localized: "settings.advanced.logs.clear"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            LogFiltersSheet(loggingService: loggingService)
        }
        #if os(tvOS)
        .sheet(isPresented: $showingExportSheet) {
            LogExportOverlayView(server: logExportServer)
        }
        #else
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [loggingService.exportLogs()])
        }
        #endif
        .sheet(item: $selectedEntry) { entry in
            LogEntryDetailView(entry: entry)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(String(localized: "settings.advanced.logs.search"), text: $loggingService.searchText)
                .textFieldStyle(.plain)

            if !loggingService.searchText.isEmpty {
                Button {
                    loggingService.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    private var logList: some View {
        Group {
            if loggingService.filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "settings.advanced.logs.empty"), systemImage: "doc.text")
                } description: {
                    if loggingService.isEnabled {
                        Text(String(localized: "settings.advanced.logs.empty.description"))
                    } else {
                        Text(String(localized: "settings.advanced.logs.disabled"))
                    }
                }
            } else {
                List(loggingService.filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntry = entry
                        }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Level indicator
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                // Header: timestamp and category
                HStack {
                    Text(entry.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text(entry.category.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                // Message
                Text(entry.message)
                    .font(.subheadline)
                    .lineLimit(2)

                // Details preview
                if let details = entry.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Log Entry Detail View

private struct LogEntryDetailView: View {
    let entry: LogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "settings.advanced.logs.detail.info")) {
                    LabeledContent(String(localized: "settings.advanced.logs.detail.timestamp")) {
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                    }

                    LabeledContent(String(localized: "settings.advanced.logs.detail.level")) {
                        HStack {
                            Image(systemName: entry.level.icon)
                            Text(entry.level.rawValue.capitalized)
                        }
                        .foregroundStyle(levelColor)
                    }

                    LabeledContent(String(localized: "settings.advanced.logs.detail.category")) {
                        HStack {
                            Image(systemName: entry.category.icon)
                            Text(entry.category.rawValue)
                        }
                    }
                }

                Section(String(localized: "settings.advanced.logs.detail.message")) {
                    Text(entry.message)
                        .font(.body)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                }

                if let details = entry.details {
                    Section(String(localized: "settings.advanced.logs.detail.details")) {
                        Text(details)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                    }
                }
            }
            .navigationTitle(String(localized: "settings.advanced.logs.detail.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Log Filters Sheet

private struct LogFiltersSheet: View {
    @Bindable var loggingService: LoggingService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "settings.advanced.logs.filter.categories")) {
                    ForEach(LogCategory.allCases, id: \.self) { category in
                        Toggle(isOn: binding(for: category)) {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                }

                Section(String(localized: "settings.advanced.logs.filter.levels")) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Toggle(isOn: binding(for: level)) {
                            Label(level.rawValue.capitalized, systemImage: level.icon)
                        }
                    }
                }

                Section {
                    Button(String(localized: "settings.advanced.logs.filter.reset")) {
                        loggingService.resetFilters()
                    }
                }
            }
            .navigationTitle(String(localized: "settings.advanced.logs.filter.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func binding(for category: LogCategory) -> Binding<Bool> {
        Binding(
            get: { loggingService.selectedCategories.contains(category) },
            set: { isSelected in
                if isSelected {
                    loggingService.selectedCategories.insert(category)
                } else {
                    loggingService.selectedCategories.remove(category)
                }
            }
        )
    }

    private func binding(for level: LogLevel) -> Binding<Bool> {
        Binding(
            get: { loggingService.selectedLevels.contains(level) },
            set: { isSelected in
                if isSelected {
                    loggingService.selectedLevels.insert(level)
                } else {
                    loggingService.selectedLevels.remove(level)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
