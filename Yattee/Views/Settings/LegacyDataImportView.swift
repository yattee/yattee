//
//  LegacyDataImportView.swift
//  Yattee
//
//  View for reviewing and re-creating accounts from the legacy v1 app.
//

import SwiftUI

struct LegacyAccountsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    var showsDoneButton = true

    @State private var items: [LegacyAccountImportItem] = []
    @State private var rowStates: [String: LegacyAccountRowState] = [:]
    @State private var isLoading = true
    @State private var pendingRemoval: LegacyAccountImportItem?
    @State private var importedInstanceName = ""
    @State private var showingImportSuccess = false

    private var legacyMigrationService: LegacyDataMigrationService? {
        appEnvironment?.legacyMigrationService
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                accountList
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
            loadLegacyAccounts()
        }
        .confirmationDialog(
            String(localized: "migration.accounts.remove.title"),
            item: $pendingRemoval,
            titleVisibility: .visible
        ) { item in
            Button(String(localized: "migration.accounts.remove.confirm"), role: .destructive) {
                removeLegacyAccount(item)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { item in
            Text(String(localized: "migration.accounts.remove.message \(item.displayName)"))
        }
        .alert(String(localized: "migration.accounts.imported.title"), isPresented: $showingImportSuccess) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(importedInstanceName)
        }
    }

    private var accountList: some View {
        Form {
            Section {
                ForEach(items) { item in
                    LegacyAccountImportRow(
                        item: item,
                        state: stateBinding(for: item)
                    ) {
                        importLegacyAccount(item)
                    } onRemove: {
                        pendingRemoval = item
                    }
                }
            } header: {
                Text(String(localized: "migration.accounts.section"))
            } footer: {
                Text(String(localized: "migration.accounts.footer"))
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

    private func loadLegacyAccounts() {
        let loadedItems = legacyMigrationService?.parseLegacyAccountsForImport() ?? []
        items = loadedItems
        for item in loadedItems where rowStates[item.legacyAccountID] == nil {
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
                importedInstanceName = importedInstance.displayName
                showingImportSuccess = true
                removeResolvedItem(item)
            } catch APIError.unauthorized {
                setImportError(String(localized: "login.error.invalidCredentials"), for: item)
            } catch {
                setImportError(error.localizedDescription, for: item)
            }
        }
    }

    private func setImportError(_ message: String, for item: LegacyAccountImportItem) {
        var state = rowStates[item.legacyAccountID] ?? LegacyAccountRowState(username: item.username)
        state.isImporting = false
        state.errorMessage = message
        rowStates[item.legacyAccountID] = state
    }

    private func removeLegacyAccount(_ item: LegacyAccountImportItem) {
        legacyMigrationService?.removeLegacyAccount(item)
        removeResolvedItem(item)
    }

    private func removeResolvedItem(_ item: LegacyAccountImportItem) {
        items.removeAll { $0.legacyAccountID == item.legacyAccountID }
        rowStates.removeValue(forKey: item.legacyAccountID)
    }
}

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
                Image(systemName: iconName)
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

    private var iconName: String {
        switch item.instanceType {
        case .invidious:
            return "server.rack"
        case .piped:
            return "cloud"
        default:
            return "globe"
        }
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
