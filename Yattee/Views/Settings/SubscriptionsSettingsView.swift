//
//  SubscriptionsSettingsView.swift
//  Yattee
//
//  Settings for importing and exporting subscriptions.
//

import SwiftUI
import UniformTypeIdentifiers

#if !os(tvOS)

// MARK: - Export File Wrapper

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct SubscriptionsSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    // Import state
    @State private var showingImportPicker = false
    @State private var isImporting = false
    @State private var importResult: (imported: Int, skipped: Int, format: String)?
    @State private var showingImportResult = false
    @State private var importError: String?
    @State private var showingImportError = false

    // Export state
    @State private var selectedExportFormat: SubscriptionExportFormat = .json
    @State private var exportFile: ExportFile?
    @State private var isExporting = false

    // Account subscription count (provider-scoped, fetched for server accounts)
    @State private var accountSubscriptionCount: Int?

    // Local data deletion state
    @State private var showingDeleteLocalConfirmation = false

    private var dataManager: DataManager? {
        appEnvironment?.dataManager
    }

    private var subscriptionService: SubscriptionService? {
        appEnvironment?.subscriptionService
    }

    /// Subscription count of the active account (local store or server).
    private var subscriptionCount: Int {
        accountSubscriptionCount ?? subscriptionService?.cachedSubscriptionCount ?? 0
    }

    /// Count of subscriptions in the local store, shown in the local-data section.
    private var localSubscriptionCount: Int {
        dataManager?.subscriptionCount ?? 0
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }

    /// What the counts and the export are actually read from.
    ///
    /// While the selected account is unavailable that is the local store — so a
    /// count or a file described as the account's would name a source it never
    /// came from. The selection itself is untouched, and the moment the account
    /// is usable again this follows it back.
    private var effectiveContext: DataContext {
        appEnvironment?.dataContextValidator.effectiveContext ?? currentContext
    }

    var body: some View {
        List {
            accountSection
            importSection
            exportSection
            localDataSection
        }
        // Keyed to the effective context, not the selection: an account going
        // unavailable — or coming back — changes which store the count is read
        // from without the selection moving at all.
        .task(id: effectiveContext) {
            await refreshAccountSubscriptionCount()
        }
        .navigationTitle(String(localized: "settings.subscriptions.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImportPicker) {
            SubscriptionFilePickerView { url in
                handleImportedFile(url)
            }
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        #endif
        .alert(
            String(localized: "settings.subscriptions.import.success.title"),
            isPresented: $showingImportResult
        ) {
            Button(String(localized: "common.ok")) {}
        } message: {
            if let result = importResult {
                Text(String(localized: "settings.subscriptions.import.success.message \(result.imported) \(result.skipped) \(result.format)"))
            }
        }
        .alert(
            String(localized: "settings.subscriptions.import.error.title"),
            isPresented: $showingImportError
        ) {
            Button(String(localized: "common.ok")) {}
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        .confirmationDialog(
            String(localized: "settings.subscriptions.localData.delete.confirmation.title \(localSubscriptionCount)"),
            isPresented: $showingDeleteLocalConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.subscriptions.localData.delete.confirmation.action"), role: .destructive) {
                deleteLocalSubscriptions()
            }
        } message: {
            Text(String(localized: "settings.subscriptions.localData.delete.confirmation.message"))
        }
        .presentationCompactAdaptation(.sheet)
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            DataContextSwitcherSettingsRow()
        } footer: {
            Text(String(localized: "settings.subscriptions.account.footer"))
        }
    }

    // MARK: - Import Section

    @ViewBuilder
    private var importSection: some View {
        Section {
            Button {
                showImportPicker()
            } label: {
                HStack {
                    Label(String(localized: "settings.subscriptions.import.button"), systemImage: "square.and.arrow.down")
                    Spacer()
                    if isImporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isImporting)
        } header: {
            Text(String(localized: "settings.subscriptions.import.title"))
        } footer: {
            Text(String(localized: "settings.subscriptions.import.footer"))
        }
    }

    // MARK: - Export Section

    @ViewBuilder
    private var exportSection: some View {
        Section {
            Picker(String(localized: "settings.subscriptions.export.format"), selection: $selectedExportFormat) {
                ForEach(SubscriptionExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }

            Button {
                exportSubscriptions()
            } label: {
                HStack {
                    Label(String(localized: "settings.subscriptions.export.button"), systemImage: "square.and.arrow.up")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(subscriptionCount == 0 || isExporting)
        } header: {
            Text(String(localized: "settings.subscriptions.export.title"))
        } footer: {
            Text(String(localized: "settings.subscriptions.export.footer \(subscriptionCount)"))
        }
    }

    // MARK: - Local Data Section

    /// Lets the user delete locally stored subscriptions while a server account
    /// is active. Hidden in local mode, where the account IS the local store.
    @ViewBuilder
    private var localDataSection: some View {
        if !currentContext.isLocal && localSubscriptionCount > 0 {
            Section {
                Button(role: .destructive) {
                    showingDeleteLocalConfirmation = true
                } label: {
                    Label(String(localized: "settings.subscriptions.localData.delete.button"), systemImage: "trash")
                }
            } header: {
                Text(String(localized: "settings.subscriptions.localData.title"))
            } footer: {
                Text(String(localized: "settings.subscriptions.localData.footer \(localSubscriptionCount)"))
            }
        }
    }

    // MARK: - Actions

    private func showImportPicker() {
        #if os(iOS)
        showingImportPicker = true
        #elseif os(macOS)
        showMacOSImportPanel()
        #endif
    }

    #if os(macOS)
    private func showMacOSImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "opml") ?? .xml,
            UTType.xml
        ]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "settings.subscriptions.import.panel.message")

        if panel.runModal() == .OK, let url = panel.url {
            handleImportedFile(url)
        }
    }
    #endif

    private func handleImportedFile(_ url: URL) {
        isImporting = true

        Task {
            do {
                // Read file data
                let data: Data
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    data = try Data(contentsOf: url)
                } else {
                    data = try Data(contentsOf: url)
                }

                // Parse subscriptions
                let parseResult = try SubscriptionImportExport.parseAuto(data)

                // Import into the active account (local store or server)
                guard let subscriptionService else {
                    throw SubscriptionImportError.invalidData
                }

                let importStats = await subscriptionService.importSubscriptions(parseResult.channels)

                await MainActor.run {
                    isImporting = false
                    importResult = (imported: importStats.imported, skipped: importStats.skipped, format: parseResult.format)
                    showingImportResult = true
                    LoggingService.shared.logSubscriptions("Import completed: \(importStats.imported) imported, \(importStats.skipped) skipped")
                }
                await refreshAccountSubscriptionCount()
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                    showingImportError = true
                    LoggingService.shared.logSubscriptionsError("Import failed", error: error)
                }
            }
        }
    }

    private func exportSubscriptions() {
        isExporting = true
        Task {
            await performExport()
            isExporting = false
        }
    }

    /// Exports subscriptions of whatever is being read from: the local store in
    /// local mode, or the server's list for Invidious/Piped accounts.
    ///
    /// The branch follows the effective context because the fetch below does —
    /// branching on the selection instead would take the server path only to
    /// export local data through it.
    private func performExport() async {
        let subscriptions: [Subscription]
        if effectiveContext.isLocal {
            guard let dataManager else { return }
            subscriptions = dataManager.allSubscriptions
        } else {
            guard let subscriptionService else { return }
            do {
                let channels = try await subscriptionService.fetchSubscriptions()
                accountSubscriptionCount = channels.count
                // Detached model instances used purely as export carriers
                subscriptions = channels.map { Subscription.from(channel: $0) }
            } catch {
                LoggingService.shared.logSubscriptionsError("Failed to fetch account subscriptions for export", error: error)
                appEnvironment?.toastManager.showError(
                    String(localized: "settings.subscriptions.export.error.title"),
                    subtitle: error.localizedDescription
                )
                return
            }
        }

        let data: Data?
        switch selectedExportFormat {
        case .json:
            data = SubscriptionImportExport.exportToJSON(subscriptions)
        case .opml:
            data = SubscriptionImportExport.exportToOPML(subscriptions)
        }

        guard let exportData = data else {
            LoggingService.shared.logSubscriptionsError("Failed to generate export data")
            return
        }

        let filename = SubscriptionImportExport.generateExportFilename(format: selectedExportFormat)

        #if os(iOS)
        // Write to temp file and share
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try exportData.write(to: tempURL)
            exportFile = ExportFile(url: tempURL)
        } catch {
            LoggingService.shared.logSubscriptionsError("Failed to write export file", error: error)
        }
        #elseif os(macOS)
        showMacOSSavePanel(data: exportData, filename: filename)
        #endif
    }

    /// Refreshes the account-scoped subscription count shown in the export footer.
    ///
    /// The context the fetch was started for is rechecked before its answer is
    /// applied. A selection change would already have been fenced by the
    /// service's provider generation, but the fallback to local is driven by the
    /// account's availability and announces nothing — so a count still in flight
    /// would otherwise land under the local heading it never came from.
    private func refreshAccountSubscriptionCount() async {
        guard let subscriptionService else { return }

        if let cached = subscriptionService.cachedSubscriptionCount {
            accountSubscriptionCount = cached
        }

        let context = effectiveContext
        if !context.isLocal {
            if let channels = try? await subscriptionService.fetchSubscriptions() {
                guard effectiveContext == context else { return }
                accountSubscriptionCount = channels.count
            }
        }
    }

    private func deleteLocalSubscriptions() {
        dataManager?.deleteAllSubscriptions()
        appEnvironment?.toastManager.showSuccess(String(localized: "settings.subscriptions.localData.deleted.title"))
        Task {
            await refreshAccountSubscriptionCount()
        }
    }

    #if os(macOS)
    private func showMacOSSavePanel(data: Data, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = selectedExportFormat == .json ? [.json] : [UTType(filenameExtension: "opml") ?? .xml]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                LoggingService.shared.logSubscriptions("Exported subscriptions to \(url.path)")
            } catch {
                LoggingService.shared.logSubscriptionsError("Failed to save export", error: error)
            }
        }
    }
    #endif
}

// MARK: - File Picker (iOS)

#if os(iOS)
struct SubscriptionFilePickerView: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .commaSeparatedText,
            UTType(filenameExtension: "opml") ?? .xml,
            .xml,
            .text
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    NavigationStack {
        SubscriptionsSettingsView()
    }
    .appEnvironment(.preview)
}
#endif
