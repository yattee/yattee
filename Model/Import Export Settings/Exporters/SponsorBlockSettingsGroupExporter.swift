import Defaults
import SwiftyJSON

final class SponsorBlockSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "sponsorBlockInstance": Defaults[.sponsorBlockInstance],
            "sponsorBlockCategories": Array(Defaults[.sponsorBlockCategories]),
            "sponsorBlockColors": Defaults[.sponsorBlockColors],
            "sponsorBlockShowTimeWithSkipsRemoved": Defaults[.sponsorBlockShowTimeWithSkipsRemoved],
            "sponsorBlockShowCategoriesInTimeline": Defaults[.sponsorBlockShowCategoriesInTimeline],
            "sponsorBlockShowNoticeAfterSkip": Defaults[.sponsorBlockShowNoticeAfterSkip]
        ]
    }
}
