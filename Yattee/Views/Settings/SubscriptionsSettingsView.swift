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

    // Account selection state
    @State private var pendingAccountChange: SubscriptionAccount?
    @State private var showingAccountSwitchConfirmation = false

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


    private var dataManager: DataManager? {
        appEnvironment?.dataManager
    }

    private var settingsManager: SettingsManager? {
        appEnvironment?.settingsManager
    }

    private var validator: SubscriptionAccountValidator? {
        appEnvironment?.subscriptionAccountValidator
    }

    private var subscriptionCount: Int {
        dataManager?.subscriptionCount ?? 0
    }

    private var currentAccount: SubscriptionAccount {
        settingsManager?.subscriptionAccount ?? .local
    }

    var body: some View {
        List {
            accountSection
            if validator?.hasAvailableAccounts == true {
                importSection
                exportSection
            }
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
            String(localized: "settings.subscriptions.account.switch.title"),
            isPresented: $showingAccountSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.subscriptions.account.switch.action")) {
                confirmAccountSwitch()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                cancelAccountSwitch()
            }
        } message: {
            Text(String(localized: "settings.subscriptions.account.switch.message"))
        }
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let validator, validator.hasAvailableAccounts {
                Picker(
                    String(localized: "settings.subscriptions.account.label"),
                    selection: Binding(
                        get: { currentAccount },
                        set: { newAccount in
                            if newAccount != currentAccount {
                                pendingAccountChange = newAccount
                                showingAccountSwitchConfirmation = true
                            }
                        }
                    )
                ) {
                    ForEach(validator.availableAccounts, id: \.self) { account in
                        Text(validator.displayName(for: account))
                            .tag(account)
                    }
                }
            } else {
                // No accounts available - show setup prompt
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        String(localized: "settings.subscriptions.account.noAccounts.title"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)

                    Text(String(localized: "settings.subscriptions.account.noAccounts.message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(String(localized: "settings.subscriptions.account.noAccounts.action")) {
                        appEnvironment?.navigationCoordinator.navigate(to: .settings)
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        } footer: {
            if validator?.hasAvailableAccounts == true {
                Text(String(localized: "settings.subscriptions.account.footer"))
            }
        }
    }

    // MARK: - Account Switch Actions

    private func confirmAccountSwitch() {
        guard let newAccount = pendingAccountChange else { return }

        settingsManager?.subscriptionAccount = newAccount
        SubscriptionFeedCache.shared.handleAccountChange()

        // Trigger feed refresh in background
        Task {
            guard let appEnvironment else { return }
            await SubscriptionFeedCache.shared.refresh(using: appEnvironment)
        }

        pendingAccountChange = nil
        LoggingService.shared.logSubscriptions("Switched subscription account to: \(String(describing: newAccount.type))")
    }

    private func cancelAccountSwitch() {
        pendingAccountChange = nil
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
                Label(String(localized: "settings.subscriptions.export.button"), systemImage: "square.and.arrow.up")
            }
            .disabled(subscriptionCount == 0)
        } header: {
            Text(String(localized: "settings.subscriptions.export.title"))
        } footer: {
            Text(String(localized: "settings.subscriptions.export.footer \(subscriptionCount)"))
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

                // Import to database
                guard let dataManager else {
                    throw SubscriptionImportError.invalidData
                }

                let importStats = dataManager.importSubscriptionsFromExternal(parseResult.channels)

                await MainActor.run {
                    isImporting = false
                    importResult = (imported: importStats.imported, skipped: importStats.skipped, format: parseResult.format)
                    showingImportResult = true
                    LoggingService.shared.logSubscriptions("Import completed: \(importStats.imported) imported, \(importStats.skipped) skipped")
                }
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
        guard let dataManager else { return }

        let subscriptions = dataManager.allSubscriptions

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
