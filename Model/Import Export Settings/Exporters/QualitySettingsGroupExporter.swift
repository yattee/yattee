import Defaults
import SwiftyJSON

final class QualitySettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "batteryCellularProfile": Defaults[.batteryCellularProfile],
            "batteryNonCellularProfile": Defaults[.batteryNonCellularProfile],
            "chargingCellularProfile": Defaults[.chargingCellularProfile],
            "chargingNonCellularProfile": Defaults[.chargingNonCellularProfile],
            "forceAVPlayerForLiveStreams": Defaults[.forceAVPlayerForLiveStreams],
            "qualityProfiles": Defaults[.qualityProfiles].compactMap { qualityProfileJSON($0) }
        ]
    }

    func qualityProfileJSON(_ profile: QualityProfile) -> JSON {
        var json = JSON()
        json.dictionaryObject = QualityProfileBridge().serialize(profile)
        return json
    }
}
