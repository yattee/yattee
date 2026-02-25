//
//  LegacyDataImportView.swift
//  Yattee
//
//  Full-screen view for importing legacy v1 data from Advanced Settings.
//

import SwiftUI

struct LegacyDataImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var items: [LegacyImportItem] = []
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var showingResultSheet = false
    @State private var lastResult: MigrationResult?
    @State private var showingUnreachableAlert = false
    @State private var pendingUnreachableItem: LegacyImportItem?

    private var legacyMigrationService: LegacyDataMigrationService? {
        appEnvironment?.legacyMigrationService
    }

    private var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "migration.noDataFound"),
                    systemImage: "doc.questionmark",
                    description: Text(String(localized: "migration.noDataFoundDescription"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                importContent
            }
        }
        .navigationTitle(String(localized: "settings.advanced.data.importLegacy"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            loadLegacyData()
        }
        .sheet(isPresented: $showingResultSheet) {
            resultSheet
        }
        .alert(String(localized: "migration.unreachableTitle"), isPresented: $showingUnreachableAlert) {
            Button(String(localized: "migration.unreachableImport"), role: .destructive) {
                // Keep the item selected
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                if let item = pendingUnreachableItem,
                   let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].isSelected = false
                }
            }
        } message: {
            Text(String(localized: "migration.unreachableMessage"))
        }
    }

    // MARK: - Import Content

    @ViewBuilder
    private var importContent: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(items) { item in
                        MigrationImportRow(item: item) {
                            toggleItem(item)
                        }
                    }
                } header: {
                    Text(String(localized: "migration.selectToImport"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "migration.accountsHint"))
                        Text(String(localized: "migration.settingsFooter"))
                    }
                }
            }

            // Bottom bar with import button
            VStack(spacing: 12) {
                Divider()

                Button(action: performImport) {
                    if isImporting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "migration.importing"))
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(String(localized: "migration.import"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedCount > 0 ? Color.accentColor : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .disabled(selectedCount == 0 || isImporting)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            #if os(tvOS)
            .background(Color(.systemGray).opacity(0.2))
            #elseif os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .systemBackground))
            #endif
        }
    }

    // MARK: - Result Sheet

    @ViewBuilder
    private var resultSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result = lastResult {
                    Spacer()

                    Image(systemName: result.isFullSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(result.isFullSuccess ? .green : .orange)

                    Text(String(localized: "migration.partialTitle"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(String(
                        format: NSLocalizedString("migration.partialMessage %lld %lld", comment: "Import result count"),
                        result.succeeded.count,
                        result.totalProcessed
                    ))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if !result.failed.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "migration.failedItems"))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ForEach(result.failed, id: \.item.id) { failure in
                                HStack {
                                    Text(failure.item.displayName)
                                        .font(.caption)
                                    Spacer()
                                    Text(failure.error.localizedDescription)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .padding()
                        #if os(tvOS)
                        .background(Color(.systemGray).opacity(0.2))
                        #elseif os(macOS)
                        .background(Color(nsColor: .controlBackgroundColor))
                        #else
                        .background(Color(uiColor: .secondarySystemBackground))
                        #endif
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        if !result.failed.isEmpty {
                            Button(action: retryFailed) {
                                Text(String(localized: "migration.retry"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        Button(action: finishImport) {
                            Text(String(localized: "migration.continue"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(result.failed.isEmpty ? Color.accentColor : Color.secondary)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .padding()
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Actions

    private func loadLegacyData() {
        items = legacyMigrationService?.parseLegacyData() ?? []
        isLoading = false
    }

    private func toggleItem(_ item: LegacyImportItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        let wasSelected = items[index].isSelected
        items[index].isSelected.toggle()

        if !wasSelected && items[index].reachabilityStatus == .unknown {
            checkReachability(for: items[index])
        }
    }

    private func checkReachability(for item: LegacyImportItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].reachabilityStatus = .checking

        Task {
            let isReachable = await legacyMigrationService?.checkReachability(for: item) ?? false

            guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[currentIndex].reachabilityStatus = isReachable ? .reachable : .unreachable

            if !isReachable && items[currentIndex].isSelected {
                pendingUnreachableItem = items[currentIndex]
                showingUnreachableAlert = true
            }
        }
    }

    private func performImport() {
        guard let service = legacyMigrationService else { return }

        isImporting = true

        Task {
            let result = await service.importItems(items)
            lastResult = result

            isImporting = false

            if result.isFullSuccess {
                dismiss()
            } else {
                showingResultSheet = true
            }
        }
    }

    private func retryFailed() {
        guard let result = lastResult else { return }

        for index in items.indices {
            let isFailed = result.failed.contains(where: { $0.item.id == items[index].id })
            items[index].isSelected = isFailed
        }

        showingResultSheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            performImport()
        }
    }

    private func finishImport() {
        showingResultSheet = false
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LegacyDataImportView()
    }
    .appEnvironment(.preview)
}
