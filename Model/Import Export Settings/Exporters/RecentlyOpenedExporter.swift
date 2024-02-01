import Defaults
import SwiftyJSON

final class RecentlyOpenedExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "recentlyOpened": Defaults[.recentlyOpened].compactMap { recentItemJSON($0) }
        ]
    }

    private func recentItemJSON(_ recentItem: RecentItem) -> JSON {
        var json = JSON()
        json.dictionaryObject = RecentItemBridge().serialize(recentItem)
        return json
    }
}
