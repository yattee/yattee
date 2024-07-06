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

        if let sponsorBlockColors = json["sponsorBlockColors"].dictionary {
            let colors = sponsorBlockColors.mapValues { json in json.stringValue }
            Defaults[.sponsorBlockColors] = colors
        }

        if let sponsorBlockShowTimeWithSkipsRemoved = json["sponsorBlockShowTimeWithSkipsRemoved"].bool {
            Defaults[.sponsorBlockShowTimeWithSkipsRemoved] = sponsorBlockShowTimeWithSkipsRemoved
        }

        if let sponsorBlockShowCategoriesInTimeline = json["sponsorBlockShowCategoriesInTimeline"].bool {
            Defaults[.sponsorBlockShowCategoriesInTimeline] = sponsorBlockShowCategoriesInTimeline
        }

        if let sponsorBlockShowNoticeAfterSkip = json["sponsorBlockShowNoticeAfterSkip"].bool {
            Defaults[.sponsorBlockShowNoticeAfterSkip] = sponsorBlockShowNoticeAfterSkip
        }
    }
}
