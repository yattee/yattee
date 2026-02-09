//
//  OnboardingMigrationScreen.swift
//  Yattee
//
//  Migration screen in the onboarding flow for importing v1 data.
//

import SwiftUI

struct OnboardingMigrationScreen: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let onContinue: () -> Void
    let onSkip: () -> Void

    @Binding var items: [LegacyImportItem]
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
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
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 50))
                    .foregroundStyle(Color.accentColor)

                Text(String(localized: "migration.title"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(String(localized: "migration.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // List of items
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "migration.selectToImport"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            MigrationImportRow(item: item) {
                                toggleItem(item)
                            }
                            .padding(.horizontal)

                            if item.id != items.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
                #if os(tvOS)
                .background(Color(.systemGray).opacity(0.2))
                #elseif os(macOS)
                .background(Color(nsColor: .controlBackgroundColor))
                #else
                .background(Color(uiColor: .secondarySystemBackground))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Hint about re-adding accounts
                Text(String(localized: "migration.accountsHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
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
                        #if os(tvOS)
                        .background(Color.accentColor.opacity(0.2))
                        #else
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        #endif
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(String(localized: "migration.import"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            #if os(tvOS)
                            .background(Color.accentColor.opacity(0.2))
                            #else
                            .background(selectedCount > 0 ? Color.accentColor : Color.gray)
                            .foregroundStyle(.white)
                            #endif
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                #if os(tvOS)
                .buttonStyle(.card)
                #endif
                .disabled(selectedCount == 0 || isImporting)

                Button(action: onSkip) {
                    Text(String(localized: "migration.skip"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .disabled(isImporting)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
        .sheet(isPresented: $showingResultSheet) {
            resultSheet
        }
        .alert(String(localized: "migration.unreachableTitle"), isPresented: $showingUnreachableAlert) {
            Button(String(localized: "migration.unreachableImport"), role: .destructive) {
                // Keep the item selected
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                // Deselect the unreachable item
                if let item = pendingUnreachableItem,
                   let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].isSelected = false
                }
            }
        } message: {
            Text(String(localized: "migration.unreachableMessage"))
        }
    }

    // MARK: - Result Sheet

    @ViewBuilder
    private var resultSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result = lastResult {
                    Spacer()

                    // Icon based on result
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

    private func toggleItem(_ item: LegacyImportItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        let wasSelected = items[index].isSelected
        items[index].isSelected.toggle()

        // If selecting and not yet checked, trigger reachability check
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

            // Show alert if unreachable and still selected
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
                onContinue()
            } else {
                // Show result sheet for partial failures
                showingResultSheet = true
            }
        }
    }

    private func retryFailed() {
        guard let result = lastResult, legacyMigrationService != nil else { return }

        // Update items to only have failed items selected
        for item in items {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                let isFailed = result.failed.contains(where: { $0.item.id == item.id })
                items[index].isSelected = isFailed
            }
        }

        showingResultSheet = false

        // Re-run import
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            performImport()
        }
    }

    private func finishImport() {
        showingResultSheet = false
        onContinue()
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var items: [LegacyImportItem] = [
        LegacyImportItem(
            id: UUID(),
            legacyInstanceID: "1",
            instanceType: .invidious,
            url: URL(string: "https://invidious.example.com")!,
            name: "My Invidious"
        ),
        LegacyImportItem(
            id: UUID(),
            legacyInstanceID: "2",
            instanceType: .piped,
            url: URL(string: "https://piped.example.com")!,
            name: nil
        )
    ]

    OnboardingMigrationScreen(
        onContinue: {},
        onSkip: {},
        items: $items
    )
    .appEnvironment(.preview)
}
