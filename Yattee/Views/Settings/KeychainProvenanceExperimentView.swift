//
//  KeychainProvenanceExperimentView.swift
//  Yattee
//
//  Debug-only driver for the Keychain provenance experiment (accounts revamp, D3).
//

#if DEBUG
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Runs the experiment described in ``KeychainProvenanceProbe``.
///
/// The protocol spans an Apple-account sign-out and sign-in, so the screen is
/// built around capturing readings rather than showing live state: each
/// "Capture report" writes a persisted snapshot that survives the switch, and
/// the whole set is copied out at the end.
struct KeychainProvenanceExperimentView: View {
    @State private var label = ""
    @State private var userRecordID: String?
    @State private var accountAvailability: CloudKitIdentity.AccountAvailability = .indeterminate
    @State private var resolvingUserRecordID = true
    @State private var reports: [KeychainProvenanceReport] = KeychainProvenanceReportStore.load()
    @State private var latestStatus: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        SettingsFormContainer {
            protocolSection
            identitySection
            runSection
            reportsSection
        }
        .navigationTitle(Text(verbatim: "Keychain Provenance"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            accountAvailability = await CloudKitIdentity.accountAvailability()
            userRecordID = await CloudKitIdentity.userRecordID()
            resolvingUserRecordID = false
        }
        .confirmationDialog(
            Text(verbatim: "Delete probe items?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                latestStatus = "Delete: " + KeychainProvenanceProbe.describe(KeychainProvenanceProbe.deleteAll())
            } label: {
                Text(verbatim: "Delete probe items")
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(verbatim: "Deletes both probe items on this device. The synchronizable one also disappears from every device signed in to the same Apple account.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var protocolSection: some View {
        SettingsFormSection(
            "Protocol",
            footer: "Two Apple accounts and a real device are required — iCloud Keychain does not behave faithfully in the Simulator. Do not press Write at steps 3 and 4: writing deletes the retained item the experiment is measuring."
        ) {
            step(1, "Signed in as account A: Write both probes.")
            step(2, "Wait ~1 minute for iCloud Keychain to sync, then Capture (label: \"A, before sign-out\").")
            step(3, "Sign out of the Apple account in system Settings, choosing to KEEP Keychain data on device. Relaunch Yattee and Capture (label: \"signed out, kept\").")
            step(4, "Sign in with account B. Relaunch Yattee and Capture (label: \"B, after switch\"). This is the decisive reading.")
            step(5, "Write both probes again under B, then Capture (label: \"B, fresh write\").")
            step(6, "Copy all reports and send them back.")
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        SettingsFormSection(
            "Identity",
            footer: "The fingerprint is an opaque hash of ubiquityIdentityToken and must differ between accounts A and B — if it does not, the sign-out did not take effect. An unavailable token does not by itself mean signed out: it also goes missing when iCloud Drive is off, which is why the account status is shown separately."
        ) {
            row("CloudKit entitlement", CloudKitAvailability.isAvailable ? "available" : "missing")
            // A nil token is ambiguous — it also means iCloud Drive is off —
            // so the account status is shown beside it rather than inferred.
            row("Ubiquity token", CloudKitIdentity.ubiquityFingerprint.map { "fp=\($0)" } ?? "unavailable")
            row("Apple account", accountStatusText)
            row("User record", resolvingUserRecordID ? "resolving…" : (userRecordID ?? "unresolved"))
        }
    }

    @ViewBuilder
    private var runSection: some View {
        SettingsFormSection(
            "Run",
            footer: "The label is stored inside the probe payload, so a report taken after an account switch still shows which account wrote the item it found."
        ) {
            TextField(text: $label) {
                Text(verbatim: "Label (e.g. \"A, before sign-out\")")
            }
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif

            actionRow("Write both probes", systemImage: "square.and.pencil") {
                writeProbes()
            }

            actionRow("Capture report", systemImage: "camera.viewfinder") {
                capture()
            }

            if let latestStatus {
                Text(verbatim: latestStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var reportsSection: some View {
        SettingsFormSection("Reports (\(reports.count))") {
            if reports.isEmpty {
                Text(verbatim: "No reports captured yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: report.label.isEmpty ? "<unlabelled>" : report.label)
                            .font(.headline)
                        Text(verbatim: report.capturedAt.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: report.text)
                            .font(.system(.caption2, design: .monospaced))
                            .selectableText()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                #if !os(tvOS)
                actionRow("Copy all reports", systemImage: "doc.on.doc") {
                    copyToClipboard(allReportsText)
                    latestStatus = "Copied \(reports.count) report(s) to the clipboard."
                }
                #endif

                actionRow("Clear reports", systemImage: "trash", role: .destructive) {
                    KeychainProvenanceReportStore.clear()
                    reports = []
                    latestStatus = "Cleared captured reports (probe items untouched)."
                }
            }

            actionRow("Delete probe items", systemImage: "key.slash", role: .destructive) {
                showingDeleteConfirmation = true
            }
        }
    }

    // MARK: - Actions

    private func writeProbes() {
        let payload = payloadText()
        let synchronizable = KeychainProvenanceProbe.write(
            account: KeychainProvenanceProbe.synchronizableAccount,
            synchronizable: true,
            payload: payload
        )
        let local = KeychainProvenanceProbe.write(
            account: KeychainProvenanceProbe.localAccount,
            synchronizable: false,
            payload: payload
        )

        latestStatus = """
        Wrote probes — synchronizable: \(KeychainProvenanceProbe.describe(synchronizable)), \
        local: \(KeychainProvenanceProbe.describe(local))
        """
    }

    private func capture() {
        let text = KeychainProvenanceReportBuilder.build(
            label: label,
            userRecordID: userRecordID,
            accountAvailability: accountAvailability
        )
        reports = KeychainProvenanceReportStore.append(
            KeychainProvenanceReport(label: label, text: text)
        )

        // Also logged so the report survives even if the app's storage is
        // reset, and so it can be exported from the log viewer on tvOS.
        LoggingService.shared.info(
            "Keychain provenance report captured",
            category: .keychain,
            details: text
        )

        latestStatus = "Captured report \(reports.count)."
    }

    private var accountStatusText: String {
        if resolvingUserRecordID { return "checking…" }
        switch accountAvailability {
        case .noAccount: return "no account signed in"
        case .available: return "signed in"
        case .indeterminate: return "could not be determined"
        }
    }

    private func payloadText() -> String {
        let fingerprint = CloudKitIdentity.ubiquityFingerprint ?? "none"
        let written = Date().formatted(.iso8601)
        return "fp=\(fingerprint)|written=\(written)|label=\(label.isEmpty ? "<unlabelled>" : label)"
    }

    private var allReportsText: String {
        reports
            .map { "\($0.text)\n" }
            .joined(separator: "\n\n========================================\n\n")
    }

    #if !os(tvOS)
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
    #endif

    // MARK: - Row builders

    @ViewBuilder
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number).")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(verbatim: text)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .selectableText()
        }
    }

    @ViewBuilder
    private func actionRow(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(role: role, action: action) {
                Label {
                    Text(verbatim: title)
                } icon: {
                    Image(systemName: systemImage)
                }
            }
            Spacer()
        }
    }
}

private extension View {
    /// tvOS has no text selection — the report is read back from the log
    /// viewer there instead.
    @ViewBuilder
    func selectableText() -> some View {
        #if os(tvOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KeychainProvenanceExperimentView()
    }
}
#endif
