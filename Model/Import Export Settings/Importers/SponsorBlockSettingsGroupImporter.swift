import Defaults
import SwiftyJSON

struct SponsorBlockSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let sponsorBlockInstance = json["sponsorBlockInstance"].string {
            Defaults[.sponsorBlockInstance] = sponsorBlockInstance
        }

        if let sponsorBlockCategories = json["sponsorBlockCategories"].array {
            Defaults[.sponsorBlockCategories] = Set(sponsorBlockCategories.compactMap { $0.string })
        }
    }
}
