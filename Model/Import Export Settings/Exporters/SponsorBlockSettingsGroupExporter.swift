import Defaults
import SwiftyJSON

final class SponsorBlockSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "sponsorBlockInstance": Defaults[.sponsorBlockInstance],
            "sponsorBlockCategories": Array(Defaults[.sponsorBlockCategories])
        ]
    }
}
