//
//  LegacyDataImportView.swift
//  Yattee
//
//  View for reviewing and re-creating accounts and sources from the legacy v1 app.
//

import SwiftUI

struct LegacyAccountsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    var showsDoneButton = true

    @State private var accountItems: [LegacyAccountImportItem] = []
    @State private var instanceItems: [LegacyInstanceImportItem] = []
    @State private var rowStates: [String: LegacyAccountRowState] = [:]
    @State private var isLoading = true
    @State private var pendingRemoval: PendingRemoval?
    @State private var importSuccessTitle = ""
    @State private var importedInstanceName = ""
    @State private var showingImportSuccess = false

    private var legacyMigrationService: LegacyDataMigrationService? {
        appEnvironment?.legacyMigrationService
    }

    private var isEmpty: Bool {
        accountItems.isEmpty && instanceItems.isEmpty
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                emptyState
            } else {
                contentList
            }
        }
        .navigationTitle(String(localized: "migration.accounts.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if !os(tvOS)
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                }
            }
            #endif
        }
        .task {
            loadLegacyData()
        }
        .confirmationDialog(
            pendingRemoval?.confirmationTitle ?? "",
            item: $pendingRemoval,
            titleVisibility: .visible
        ) { removal in
            Button(String(localized: "migration.accounts.remove.confirm"), role: .destructive) {
                confirmRemoval(removal)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { removal in
            Text(String(localized: "migration.accounts.remove.message \(removal.displayName)"))
        }
        .alert(importSuccessTitle, isPresented: $showingImportSuccess) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(importedInstanceName)
        }
    }

    private var contentList: some View {
        Form {
            if !accountItems.isEmpty {
                Section {
                    ForEach(accountItems) { item in
                        LegacyAccountImportRow(
                            item: item,
                            state: stateBinding(for: item)
                        ) {
                            importLegacyAccount(item)
                        } onRemove: {
                            pendingRemoval = .account(item)
                        }
                    }
                } header: {
                    Text(String(localized: "migration.accounts.section"))
                } footer: {
                    Text(String(localized: "migration.accounts.footer"))
                }
            }

            if !instanceItems.isEmpty {
                Section {
                    ForEach(instanceItems) { item in
                        LegacyInstanceImportRow(item: item) {
                            importLegacyInstance(item)
                        } onRemove: {
                            pendingRemoval = .instance(item)
                        }
                    }
                } header: {
                    Text(String(localized: "migration.sources.section"))
                } footer: {
                    Text(String(localized: "migration.sources.footer"))
                }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "migration.accounts.empty.title"),
            systemImage: "person.badge.key",
            description: Text(String(localized: "migration.accounts.empty.description"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadLegacyData() {
        let loadedAccounts = legacyMigrationService?.parseLegacyAccountsForImport() ?? []
        accountItems = loadedAccounts
        instanceItems = legacyMigrationService?.parseLegacyInstancesForImport() ?? []
        for item in loadedAccounts where rowStates[item.legacyAccountID] == nil {
            rowStates[item.legacyAccountID] = LegacyAccountRowState(username: item.username)
        }
        isLoading = false
    }

    private func stateBinding(for item: LegacyAccountImportItem) -> Binding<LegacyAccountRowState> {
        Binding {
            rowStates[item.legacyAccountID] ?? LegacyAccountRowState(username: item.username)
        } set: { newValue in
            rowStates[item.legacyAccountID] = newValue
        }
    }

    private func importLegacyAccount(_ item: LegacyAccountImportItem) {
        guard let service = legacyMigrationService else { return }
        var state = rowStates[item.legacyAccountID] ?? LegacyAccountRowState(username: item.username)
        state.isImporting = true
        state.errorMessage = nil
        rowStates[item.legacyAccountID] = state

        Task {
            do {
                let importedInstance = try await service.importLegacyAccount(
                    item,
                    username: state.username,
                    password: state.password
                )
                importSuccessTitle = String(localized: "migration.accounts.imported.title")
                importedInstanceName = importedInstance.displayName
                showingImportSuccess = true
                accountItems.removeAll { $0.legacyAccountID == item.legacyAccountID }
                rowStates.removeValue(forKey: item.legacyAccountID)
            } catch APIError.unauthorized {
                setImportError(String(localized: "login.error.invalidCredentials"), for: item)
            } catch {
                setImportError(error.localizedDescription, for: item)
            }
        }
    }

    private func importLegacyInstance(_ item: LegacyInstanceImportItem) {
        guard let service = legacyMigrationService else { return }
        let importedInstance = service.importLegacyInstance(item)
        importSuccessTitle = String(localized: "migration.sources.imported.title")
        importedInstanceName = importedInstance.displayName
        showingImportSuccess = true
        instanceItems.removeAll { $0.legacyInstanceID == item.legacyInstanceID }
    }

    private func setImportError(_ message: String, for item: LegacyAccountImportItem) {
        var state = rowStates[item.legacyAccountID] ?? LegacyAccountRowState(username: item.username)
        state.isImporting = false
        state.errorMessage = message
        rowStates[item.legacyAccountID] = state
    }

    private func confirmRemoval(_ removal: PendingRemoval) {
        switch removal {
        case .account(let item):
            legacyMigrationService?.removeLegacyAccount(item)
            accountItems.removeAll { $0.legacyAccountID == item.legacyAccountID }
            rowStates.removeValue(forKey: item.legacyAccountID)
        case .instance(let item):
            legacyMigrationService?.removeLegacyInstance(item)
            instanceItems.removeAll { $0.legacyInstanceID == item.legacyInstanceID }
        }
    }
}

// MARK: - Pending Removal

private enum PendingRemoval: Identifiable {
    case account(LegacyAccountImportItem)
    case instance(LegacyInstanceImportItem)

    var id: String {
        switch self {
        case .account(let item):
            return "account:\(item.id)"
        case .instance(let item):
            return "instance:\(item.id)"
        }
    }

    var displayName: String {
        switch self {
        case .account(let item):
            return item.displayName
        case .instance(let item):
            return item.instanceDisplayName
        }
    }

    var confirmationTitle: String {
        switch self {
        case .account:
            return String(localized: "migration.accounts.remove.title")
        case .instance:
            return String(localized: "migration.sources.remove.title")
        }
    }
}

// MARK: - Account Row

private struct LegacyAccountImportRow: View {
    let item: LegacyAccountImportItem
    @Binding var state: LegacyAccountRowState
    let onImport: () -> Void
    let onRemove: () -> Void

    private var canImport: Bool {
        !state.username.isEmpty && !state.password.isEmpty && !state.isImporting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: legacyInstanceIcon(for: item.instanceType))
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.headline)

                    Text(item.instanceDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(item.url.host ?? item.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            credentialsFields

            if let errorMessage = state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(role: .destructive, action: onRemove) {
                    Text(String(localized: "common.remove"))
                }
                .disabled(state.isImporting)
                .foregroundStyle(.red)
                .tint(.red)

                Spacer()

                Button(action: onImport) {
                    if state.isImporting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "migration.importing"))
                        }
                    } else {
                        Text(String(localized: "migration.import"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canImport)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var credentialsFields: some View {
        #if os(tvOS)
        TVSettingsTextField(title: usernameLabel, text: $state.username)
        TVSettingsTextField(title: String(localized: "login.password"), text: $state.password, isSecure: true)
        #else
        TextField(usernameLabel, text: $state.username)
            .textContentType(.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

        SecureField(String(localized: "login.password"), text: $state.password)
            .textContentType(.password)
        #endif
    }

    private var usernameLabel: String {
        switch item.instanceType {
        case .invidious:
            return String(localized: "login.email")
        default:
            return String(localized: "login.username")
        }
    }
}

// MARK: - Source Row

private struct LegacyInstanceImportRow: View {
    let item: LegacyInstanceImportItem
    let onImport: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: legacyInstanceIcon(for: item.instanceType))
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.instanceDisplayName)
                        .font(.headline)

                    Text(item.url.host ?? item.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack {
                Button(role: .destructive, action: onRemove) {
                    Text(String(localized: "common.remove"))
                }
                .foregroundStyle(.red)
                .tint(.red)

                Spacer()

                Button(action: onImport) {
                    Text(String(localized: "migration.import"))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
    }
}

private func legacyInstanceIcon(for type: InstanceType) -> String {
    switch type {
    case .invidious:
        return "server.rack"
    case .piped:
        return "cloud"
    default:
        return "globe"
    }
}

private struct LegacyAccountRowState: Equatable {
    var username: String
    var password = ""
    var errorMessage: String?
    var isImporting = false
}

struct LegacyDataImportView: View {
    var body: some View {
        LegacyAccountsImportView()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LegacyAccountsImportView()
    }
    .appEnvironment(.preview)
}
