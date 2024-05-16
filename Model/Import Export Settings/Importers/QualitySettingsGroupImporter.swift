import Defaults
import SwiftyJSON

struct QualitySettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let batteryCellularProfileString = json["batteryCellularProfile"].string {
            Defaults[.batteryCellularProfile] = batteryCellularProfileString
        }

        if let batteryNonCellularProfileString = json["batteryNonCellularProfile"].string {
            Defaults[.batteryNonCellularProfile] = batteryNonCellularProfileString
        }

        if let chargingCellularProfileString = json["chargingCellularProfile"].string {
            Defaults[.chargingCellularProfile] = chargingCellularProfileString
        }

        if let chargingNonCellularProfileString = json["chargingNonCellularProfile"].string {
            Defaults[.chargingNonCellularProfile] = chargingNonCellularProfileString
        }

        if let forceAVPlayerForLiveStreams = json["forceAVPlayerForLiveStreams"].bool {
            Defaults[.forceAVPlayerForLiveStreams] = forceAVPlayerForLiveStreams
        }

        if let qualityProfiles = json["qualityProfiles"].array {
            for qualityProfileJSON in qualityProfiles {
                let dict = qualityProfileJSON.dictionaryValue.mapValues { json in json.stringValue }
                if let item = QualityProfileBridge().deserialize(dict) {
                    QualityProfilesModel.shared.update(item, item)
                }
            }
        }
    }
}
