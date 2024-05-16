import Defaults
import SwiftyJSON

struct RecentlyOpenedImporter {
    var json: JSON

    func performImport() {
        if let recentlyOpened = json["recentlyOpened"].array {
            for recentlyOpenedJSON in recentlyOpened {
                let dict = recentlyOpenedJSON.dictionaryValue.mapValues { json in json.stringValue }
                if let item = RecentItemBridge().deserialize(dict) {
                    RecentsModel.shared.add(item)
                }
            }
        }
    }
}
