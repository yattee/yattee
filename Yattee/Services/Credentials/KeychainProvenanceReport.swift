//
//  KeychainProvenanceReport.swift
//  Yattee
//
//  Captures and persists the output of KeychainProvenanceProbe so results
//  survive the Apple-account sign-out/sign-in steps of the experiment.
//

#if DEBUG
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// One captured run of the experiment.
///
/// Reports are persisted because the protocol spans an Apple-account sign-out
/// and sign-in: the reading taken *before* the switch is half the evidence, and
/// it must still be readable after it.
struct KeychainProvenanceReport: Codable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let label: String
    let text: String

    init(id: UUID = UUID(), capturedAt: Date = Date(), label: String, text: String) {
        self.id = id
        self.capturedAt = capturedAt
        self.label = label
        self.text = text
    }
}

/// UserDefaults-backed store for captured reports.
///
/// Deliberately not synced anywhere — the whole point is a per-device record.
enum KeychainProvenanceReportStore {
    private static let defaultsKey = "debug.keychainProvenanceReports"

    static func load() -> [KeychainProvenanceReport] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let reports = try? JSONDecoder().decode([KeychainProvenanceReport].self, from: data)
        else { return [] }
        return reports
    }

    static func append(_ report: KeychainProvenanceReport) -> [KeychainProvenanceReport] {
        let reports = load() + [report]
        save(reports)
        return reports
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func save(_ reports: [KeychainProvenanceReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - Report text

enum KeychainProvenanceReportBuilder {
    /// Builds the full plain-text report for the current device state.
    ///
    /// - Parameters:
    ///   - label: free-form run label, e.g. "iPhone 15 — signed in as identity B".
    ///   - userRecordID: resolved asynchronously by the caller (network), `nil`
    ///     when unavailable.
    static func build(
        label: String,
        userRecordID: String?,
        accountAvailability: CloudKitIdentity.AccountAvailability
    ) -> String {
        let results = KeychainProvenanceProbe.queryAll()

        var lines: [String] = []
        lines.append("=== Yattee Keychain provenance experiment ===")
        lines.append("Label:        \(label.isEmpty ? "<unlabelled>" : label)")
        lines.append("Captured:     \(iso(Date()))")
        lines.append("Platform:     \(platformDescription)")
        lines.append("")

        lines.append("--- Identity ---")
        lines.append("CloudKit entitlement: \(CloudKitAvailability.isAvailable ? "available" : "missing (sideload)")")
        // A nil token does NOT mean signed out — Foundation also returns nil
        // when iCloud Drive is off, so the report must not assert either way.
        // CloudKit's account status is what disambiguates.
        lines.append("ubiquityIdentityToken: \(CloudKitIdentity.ubiquityFingerprint.map { "present, fp=\($0)" } ?? "unavailable (signed out, or iCloud Drive off)")")
        lines.append("CloudKit account:      \(describe(accountAvailability))")
        lines.append("CloudKit user record:  \(userRecordID ?? "unresolved")")
        lines.append("")

        lines.append("--- Keychain queries (service \(KeychainProvenanceProbe.service)) ---")
        for result in results {
            lines.append("")
            lines.append("[\(result.match.label)]")
            lines.append("  status: \(KeychainProvenanceProbe.describe(result.status)), \(result.items.count) item(s)")
            for item in result.items {
                lines.append("  • account=\(item.account)")
                lines.append("      stored synchronizable: \(item.synchronizable.map(String.init(describing:)) ?? "absent")")
                lines.append("      accessible:            \(item.accessible ?? "absent")")
                lines.append("      created:               \(item.creationDate.map(iso) ?? "absent")")
                lines.append("      modified:              \(item.modificationDate.map(iso) ?? "absent")")
                lines.append("      payload:               \(item.payload ?? "<not utf8>")")
            }
        }

        lines.append("")
        lines.append("--- Discriminator check ---")
        lines.append(contentsOf: discriminatorLines(results))

        return lines.joined(separator: "\n")
    }

    /// Compares what the candidate discriminator matched against what Yattee's
    /// current `SynchronizableAny` query matches — the difference is exactly
    /// what auto-adoption would refuse to adopt.
    private static func discriminatorLines(
        _ results: [KeychainProvenanceProbe.QueryResult]
    ) -> [String] {
        let strict = Set(results.first { $0.match == .synchronizableTrue }?.items.map(\.account) ?? [])
        let any = Set(results.first { $0.match == .any }?.items.map(\.account) ?? [])

        var lines: [String] = []
        lines.append("matched by strict `== true`: \(format(strict))")
        lines.append("matched by `Any` (today):    \(format(any))")
        lines.append("visible to Yattee but NOT provenance-backed: \(format(any.subtracting(strict)))")
        return lines
    }

    private static func format(_ accounts: Set<String>) -> String {
        accounts.isEmpty ? "none" : accounts.sorted().joined(separator: ", ")
    }

    private static func describe(_ availability: CloudKitIdentity.AccountAvailability) -> String {
        switch availability {
        case .noAccount: "no account signed in"
        case .available: "signed in"
        case .indeterminate: "could not be determined"
        }
    }

    // MARK: - Environment

    private static var platformDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(iOS)
        return "iOS — \(UIDevice.current.model) — \(version)"
        #elseif os(tvOS)
        return "tvOS — \(UIDevice.current.model) — \(version)"
        #elseif os(macOS)
        return "macOS — \(version)"
        #else
        return version
        #endif
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
#endif
