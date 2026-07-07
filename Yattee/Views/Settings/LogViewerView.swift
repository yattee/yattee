//
//  LogViewerView.swift
//  Yattee
//
//  In-app log viewer for debugging.
//

import SwiftUI
import UniformTypeIdentifiers

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
            searchBar

            // Log list
            logList
        }
        .opaqueSettingsFormBackground()
        .navigationTitle(String(localized: "settings.advanced.logs.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFilters = true
                } label: {
                    Label(String(localized: "settings.advanced.logs.filter"), systemImage: "line.3.horizontal.decrease.circle")
                }
                .help(String(localized: "settings.advanced.logs.filter"))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showMacOSSavePanel()
                } label: {
                    Label(String(localized: "settings.advanced.logs.export"), systemImage: "square.and.arrow.up")
                }
                .help(String(localized: "settings.advanced.logs.export"))
            }

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    loggingService.clearLogs()
                } label: {
                    Label(String(localized: "settings.advanced.logs.clear"), systemImage: "trash")
                }
                .help(String(localized: "settings.advanced.logs.clear"))
            }
            #else
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
            #endif
        }
        .sheet(isPresented: $showingFilters) {
            LogFiltersSheet(loggingService: loggingService)
        }
        #if os(tvOS)
        .sheet(isPresented: $showingExportSheet) {
            LogExportOverlayView(server: logExportServer)
        }
        #elseif os(iOS)
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [loggingService.exportLogs()])
        }
        #endif
        .sheet(item: $selectedEntry) { entry in
            LogEntryDetailView(entry: entry)
        }
    }

    #if os(macOS)
    private func showMacOSSavePanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Yattee Logs \(Date.now.formatted(.iso8601.year().month().day())).txt"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try Data(loggingService.exportLogs().utf8).write(to: url)
            } catch {
                loggingService.log(level: .error, category: .general, message: "Failed to save logs export", details: error.localizedDescription)
            }
        }
    }
    #endif

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            SettingsFormContainer {
                SettingsFormSection("settings.advanced.logs.detail.info") {
                    HStack {
                        Text(String(localized: "settings.advanced.logs.detail.timestamp"))
                        Spacer()
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(String(localized: "settings.advanced.logs.detail.level"))
                        Spacer()
                        HStack {
                            Image(systemName: entry.level.icon)
                            Text(entry.level.rawValue.capitalized)
                        }
                        .foregroundStyle(levelColor)
                    }

                    HStack {
                        Text(String(localized: "settings.advanced.logs.detail.category"))
                        Spacer()
                        HStack {
                            Image(systemName: entry.category.icon)
                            Text(entry.category.rawValue)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                SettingsFormSection("settings.advanced.logs.detail.message") {
                    Text(entry.message)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                }

                if let details = entry.details {
                    SettingsFormSection("settings.advanced.logs.detail.details") {
                        Text(details)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                sheetCloseToolbarItem { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
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
            SettingsFormContainer {
                SettingsFormSection("settings.advanced.logs.filter.categories") {
                    ForEach(LogCategory.allCases, id: \.self) { category in
                        Toggle(isOn: binding(for: category)) {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                }
                #if os(macOS)
                .labelStyle(FixedIconWidthLabelStyle())
                #endif

                SettingsFormSection("settings.advanced.logs.filter.levels") {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Toggle(isOn: binding(for: level)) {
                            Label(level.rawValue.capitalized, systemImage: level.icon)
                        }
                    }
                }
                #if os(macOS)
                .labelStyle(FixedIconWidthLabelStyle())
                #endif

                HStack {
                    Button(String(localized: "settings.advanced.logs.filter.reset")) {
                        loggingService.resetFilters()
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
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
                        Text(String(localized: "common.close"))
                    }
                }
            }
        }
        .presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
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
