import Defaults
import Foundation
import SwiftyJSON

final class ImportSettingsFileModel: ObservableObject {
    static let shared = ImportSettingsFileModel()

    var locationsSettingsGroupImporter: LocationsSettingsGroupImporter? {
        if let locationsSettings = json.dictionaryValue["locationsSettings"] {
            return LocationsSettingsGroupImporter(
                json: locationsSettings,
                includePublicLocations: importExportModel.isGroupEnabled(.locationsSettings),
                includedInstancesIDs: sheetViewModel.selectedInstances,
                includedAccountsIDs: sheetViewModel.selectedAccounts,
                includedAccountsPasswords: sheetViewModel.importableAccountsPasswords
            )
        }
        return nil
    }

    var importExportModel = ImportExportSettingsModel.shared
    var sheetViewModel = ImportSettingsSheetViewModel.shared

    var loadTask: URLSessionTask?

    func isGroupIncludedInFile(_ group: ImportExportSettingsModel.ExportGroup) -> Bool {
        switch group {
        case .locationsSettings:
            return isPublicInstancesSettingsGroupInFile || instancesOrAccountsInFile
        default:
            return !groupJSON(group).isEmpty
        }
    }

    var isPublicInstancesSettingsGroupInFile: Bool {
        guard let dict = groupJSON(.locationsSettings).dictionary else { return false }

        return dict.keys.contains("instancesManifest") || dict.keys.contains("countryOfPublicInstances")
    }

    var instancesOrAccountsInFile: Bool {
        guard let dict = groupJSON(.locationsSettings).dictionary else { return false }

        return (dict.keys.contains("instances") && !(dict["instances"]?.arrayValue.isEmpty ?? true)) ||
            (dict.keys.contains("accounts") && !(dict["accounts"]?.arrayValue.isEmpty ?? true))
    }

    func groupJSON(_ group: ImportExportSettingsModel.ExportGroup) -> JSON {
        json.dictionaryValue[group.rawValue] ?? .init()
    }

    func performImport() {
        if importExportModel.isGroupSelected(.browsingSettings), isGroupIncludedInFile(.browsingSettings) {
            BrowsingSettingsGroupImporter(json: groupJSON(.browsingSettings)).performImport()
        }

        if importExportModel.isGroupSelected(.playerSettings), isGroupIncludedInFile(.playerSettings) {
            PlayerSettingsGroupImporter(json: groupJSON(.playerSettings)).performImport()
        }

        if importExportModel.isGroupSelected(.controlsSettings), isGroupIncludedInFile(.controlsSettings) {
            ConstrolsSettingsGroupImporter(json: groupJSON(.controlsSettings)).performImport()
        }

        if importExportModel.isGroupSelected(.qualitySettings), isGroupIncludedInFile(.qualitySettings) {
            QualitySettingsGroupImporter(json: groupJSON(.qualitySettings)).performImport()
        }

        if importExportModel.isGroupSelected(.historySettings), isGroupIncludedInFile(.historySettings) {
            HistorySettingsGroupImporter(json: groupJSON(.historySettings)).performImport()
        }

        if importExportModel.isGroupSelected(.sponsorBlockSettings), isGroupIncludedInFile(.sponsorBlockSettings) {
            SponsorBlockSettingsGroupImporter(json: groupJSON(.sponsorBlockSettings)).performImport()
        }

        locationsSettingsGroupImporter?.performImport()

        if importExportModel.isGroupSelected(.advancedSettings), isGroupIncludedInFile(.advancedSettings) {
            AdvancedSettingsGroupImporter(json: groupJSON(.advancedSettings)).performImport()
        }

        if importExportModel.isGroupSelected(.recentlyOpened), isGroupIncludedInFile(.recentlyOpened) {
            RecentlyOpenedImporter(json: groupJSON(.recentlyOpened)).performImport()
        }

        if importExportModel.isGroupSelected(.otherData), isGroupIncludedInFile(.otherData) {
            OtherDataSettingsGroupImporter(json: groupJSON(.otherData)).performImport()
        }
    }

    @Published var json = JSON()

    func loadData(_ url: URL) {
        json = JSON()
        loadTask?.cancel()

        loadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }

            if let json = try? JSON(data: data) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.json = json

                    self.sheetViewModel.reset(locationsSettingsGroupImporter)
                    self.importExportModel.reset(self)
                }
            }
        }
        loadTask?.resume()
    }

    func filename(_ url: URL) -> String {
        String(url.lastPathComponent.dropLast(ImportExportSettingsModel.settingsExtension.count + 1))
    }

    var metadataBuild: String? {
        if let build = json.dictionaryValue["metadata"]?.dictionaryValue["build"]?.string {
            return build
        }

        return nil
    }

    var metadataPlatform: String? {
        if let platform = json.dictionaryValue["metadata"]?.dictionaryValue["platform"]?.string {
            return platform
        }

        return nil
    }

    var metadataDate: String? {
        if let timestamp = json.dictionaryValue["metadata"]?.dictionaryValue["timestamp"]?.doubleValue {
            let date = Date(timeIntervalSince1970: timestamp)
            return dateFormatter.string(from: date)
        }

        return nil
    }

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium

        return formatter
    }
}
