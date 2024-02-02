import Defaults
import Foundation
import SwiftUI
import SwiftyJSON

final class ImportExportSettingsModel: ObservableObject {
    static let shared = ImportExportSettingsModel()

    static var exportFile: URL {
        YatteeApp.settingsExportDirectory
            .appendingPathComponent("Yattee Settings from \(Constants.deviceName).\(settingsExtension)")
    }

    static var settingsExtension: String {
        "yatteesettings"
    }

    enum ExportGroup: String, Identifiable, CaseIterable {
        case browsingSettings
        case playerSettings
        case controlsSettings
        case qualitySettings
        case historySettings
        case sponsorBlockSettings
        case advancedSettings

        case locationsSettings
        case instances
        case accounts
        case accountsUnencryptedPasswords

        case recentlyOpened
        case otherData

        static var settingsGroups: [Self] {
            [.browsingSettings, .playerSettings, .controlsSettings, .qualitySettings, .historySettings, .sponsorBlockSettings, .advancedSettings]
        }

        static var locationsGroups: [Self] {
            [.locationsSettings, .instances, .accounts, .accountsUnencryptedPasswords]
        }

        static var otherGroups: [Self] {
            [.recentlyOpened, .otherData]
        }

        var id: RawValue {
            rawValue
        }

        var label: String {
            switch self {
            case .browsingSettings:
                return "Browsing"
            case .playerSettings:
                return "Player"
            case .controlsSettings:
                return "Controls"
            case .qualitySettings:
                return "Quality"
            case .historySettings:
                return "History"
            case .sponsorBlockSettings:
                return "SponsorBlock"
            case .locationsSettings:
                return "Public Locations"
            case .instances:
                return "Custom Locations"
            case .accounts:
                return "Accounts"
            case .accountsUnencryptedPasswords:
                return "Accounts passwords (unencrypted)"
            case .advancedSettings:
                return "Advanced"
            case .recentlyOpened:
                return "Recents"
            case .otherData:
                return "Other data"
            }
        }
    }

    @Published var selectedExportGroups = Set<ExportGroup>()
    static var defaultExportGroups = Set<ExportGroup>([
        .browsingSettings,
        .playerSettings,
        .controlsSettings,
        .qualitySettings,
        .historySettings,
        .sponsorBlockSettings,
        .locationsSettings,
        .instances,
        .accounts,
        .advancedSettings
    ])

    @Published var isExportInProgress = false

    private var navigation = NavigationModel.shared
    private var settings = SettingsModel.shared

    func toggleExportGroupSelection(_ group: ExportGroup) {
        if isGroupSelected(group) {
            selectedExportGroups.remove(group)
        } else {
            selectedExportGroups.insert(group)
        }

        removeNotEnabledSelectedGroups()
    }

    func reset() {
        isExportInProgress = false
        selectedExportGroups = Self.defaultExportGroups
    }

    func reset(_ model: ImportSettingsFileModel? = nil) {
        reset()

        guard let model else { return }

        selectedExportGroups = selectedExportGroups.filter { model.isGroupIncludedInFile($0) }
    }

    func exportAction() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            var writingOptions: JSONSerialization.WritingOptions = []
            #if DEBUG
                writingOptions.insert(.prettyPrinted)
                writingOptions.insert(.sortedKeys)
            #endif
            try? self?.jsonForExport?.rawString(options: writingOptions)?.write(to: Self.exportFile, atomically: true, encoding: String.Encoding.utf8)
            #if os(macOS)
                DispatchQueue.main.async { [weak self] in
                    self?.isExportInProgress = false
                }
                NSWorkspace.shared.selectFile(Self.exportFile.path, inFileViewerRootedAtPath: YatteeApp.settingsExportDirectory.path)
            #endif
        }
    }

    private var jsonForExport: JSON? {
        [
            "metadata": metadataJSON,
            "browsingSettings": selectedExportGroups.contains(.browsingSettings) ? BrowsingSettingsGroupExporter().exportJSON : JSON(),
            "playerSettings": selectedExportGroups.contains(.playerSettings) ? PlayerSettingsGroupExporter().exportJSON : JSON(),
            "controlsSettings": selectedExportGroups.contains(.controlsSettings) ? ConstrolsSettingsGroupExporter().exportJSON : JSON(),
            "qualitySettings": selectedExportGroups.contains(.qualitySettings) ? QualitySettingsGroupExporter().exportJSON : JSON(),
            "historySettings": selectedExportGroups.contains(.historySettings) ? HistorySettingsGroupExporter().exportJSON : JSON(),
            "sponsorBlockSettings": selectedExportGroups.contains(.sponsorBlockSettings) ? SponsorBlockSettingsGroupExporter().exportJSON : JSON(),
            "locationsSettings": LocationsSettingsGroupExporter(
                includePublicInstances: isGroupSelected(.locationsSettings),
                includeInstances: isGroupSelected(.instances),
                includeAccounts: isGroupSelected(.accounts),
                includeAccountsUnencryptedPasswords: isGroupSelected(.accountsUnencryptedPasswords)
            ).exportJSON,
            "advancedSettings": selectedExportGroups.contains(.advancedSettings) ? AdvancedSettingsGroupExporter().exportJSON : JSON(),
            "recentlyOpened": selectedExportGroups.contains(.recentlyOpened) ? RecentlyOpenedExporter().exportJSON : JSON(),
            "otherData": selectedExportGroups.contains(.otherData) ? OtherDataSettingsGroupExporter().exportJSON : JSON()
        ]
    }

    private var metadataJSON: JSON {
        [
            "build": YatteeApp.build,
            "timestamp": "\(Date().timeIntervalSince1970)",
            "platform": Constants.platform
        ]
    }

    func isGroupSelected(_ group: ExportGroup) -> Bool {
        selectedExportGroups.contains(group)
    }

    func isGroupEnabled(_ group: ExportGroup) -> Bool {
        switch group {
        case .accounts:
            return selectedExportGroups.contains(.instances)
        case .accountsUnencryptedPasswords:
            return selectedExportGroups.contains(.instances) && selectedExportGroups.contains(.accounts)
        default:
            return true
        }
    }

    func removeNotEnabledSelectedGroups() {
        selectedExportGroups = selectedExportGroups.filter { isGroupEnabled($0) }
    }

    var isExportAvailable: Bool {
        !selectedExportGroups.isEmpty && !isExportInProgress
    }
}
