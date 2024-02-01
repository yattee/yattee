import Defaults
import SwiftyJSON

struct RecentlyOpenedImporter {
    var json: JSON

    func performImport() {
        if let recentlyOpened = json["recentlyOpened"].array {
            recentlyOpened.forEach { recentlyOpenedJSON in
                let dict = recentlyOpenedJSON.dictionaryValue.mapValues { json in json.stringValue }
                if let item = RecentItemBridge().deserialize(dict) {
                    RecentsModel.shared.add(item)
                }
            }
        }
    }
}
