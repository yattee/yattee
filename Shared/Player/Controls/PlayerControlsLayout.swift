import Defaults
import Foundation
#if os(iOS)
    import UIKit
#endif

enum PlayerControlsLayout: String, CaseIterable, Defaults.Serializable {
    case tvRegular
    case veryLarge
    case large
    case medium
    case small
    case smaller

    var available: Bool {
        var isATV = false
        var isIPad = false
        #if os(tvOS)
            isATV = true
        #endif
        #if os(iOS)
            isIPad = UIDevice.current.userInterfaceIdiom == .pad
        #endif
        switch self {
        case .tvRegular:
            return isATV
        case .veryLarge:
            #if os(macOS)
                return true
            #else
                return isIPad
            #endif
        case .large:
            return true
        case .medium:
            return true
        case .small:
            return true
        case .smaller:
            return true
        }
    }

    var description: String {
        switch self {
        case .tvRegular:
            return "TV".localized()
        case .veryLarge:
            return "Very Large".localized()
        default:
            return rawValue.capitalized.localized()
        }
    }

    var buttonsSpacing: Double {
        switch self {
        case .tvRegular:
            return 80
        case .veryLarge:
            return 40
        case .large:
            return 25
        case .medium:
            return 25
        case .small:
            return 20
        case .smaller:
            return 20
        }
    }

    var buttonFontSize: Double {
        switch self {
        case .tvRegular:
            return 48
        case .veryLarge:
            return 35
        case .large:
            return 28
        case .medium:
            return 22
        case .small:
            return 18
        case .smaller:
            return 15
        }
    }

    var bigButtonFontSize: Double {
        switch self {
        case .tvRegular:
            return 65
        case .veryLarge:
            return 55
        case .large:
            return 45
        case .medium:
            return 35
        case .small:
            return 30
        case .smaller:
            return 25
        }
    }

    var buttonSize: Double {
        switch self {
        case .tvRegular:
            return 90
        case .veryLarge:
            return 60
        case .large:
            return 45
        case .medium:
            return 35
        case .small:
            return 30
        case .smaller:
            return 25
        }
    }

    var bigButtonSize: Double {
        switch self {
        case .tvRegular:
            return 100
        case .veryLarge:
            return 85
        case .large:
            return 70
        case .medium:
            return 60
        case .small:
            return 60
        case .smaller:
            return 60
        }
    }

    var segmentFontSize: Double {
        switch self {
        case .tvRegular:
            return 20
        case .veryLarge:
            return 16
        case .large:
            return 12
        case .medium:
            return 10
        case .small:
            return 9
        case .smaller:
            return 9
        }
    }

    var chapterFontSize: Double {
        switch self {
        case .tvRegular:
            return 24
        case .veryLarge:
            return 20
        case .large:
            return 16
        case .medium:
            return 12
        case .small:
            return 10
        case .smaller:
            return 10
        }
    }

    var projectedTimeFontSize: Double {
        switch self {
        case .tvRegular:
            return 30
        case .veryLarge:
            return 25
        case .large:
            return 20
        case .medium:
            return 15
        case .small:
            return 13
        case .smaller:
            return 11
        }
    }

    var timeFontSize: Double {
        switch self {
        case .tvRegular:
            return 45
        case .veryLarge:
            return 35
        case .large:
            return 28
        case .medium:
            return 17
        case .small:
            return 13
        case .smaller:
            return 9
        }
    }

    var bufferingStateFontSize: Double {
        switch self {
        case .tvRegular:
            return 45
        case .veryLarge:
            return 30
        case .large:
            return 24
        case .medium:
            return 14
        case .small:
            return 10
        case .smaller:
            return 7
        }
    }

    var timeLeadingEdgePadding: Double {
        switch self {
        case .tvRegular:
            return 20
        case .veryLarge:
            return 5
        case .large:
            return 5
        case .medium:
            return 5
        case .small:
            return 3
        case .smaller:
            return 3
        }
    }

    var timeTrailingEdgePadding: Double {
        timeLeadingEdgePadding
    }

    var timelineHeight: Double {
        switch self {
        case .tvRegular:
            return 80
        case .veryLarge:
            return 40
        case .large:
            return 35
        case .medium:
            return 30
        case .small:
            return 25
        case .smaller:
            return 20
        }
    }

    var seekOSDWidth: Double {
        switch self {
        case .tvRegular:
            return 280
        case .veryLarge:
            return 240
        case .large:
            return 200
        case .medium:
            return 180
        case .small:
            return 140
        case .smaller:
            return 120
        }
    }

    var osdVerticalOffset: Double {
        buttonSize
    }

    var osdProgressBarHeight: Double {
        switch self {
        case .tvRegular:
            return 20
        case .veryLarge:
            return 10
        case .large:
            return 8
        case .medium:
            return 5
        case .small:
            return 5
        case .smaller:
            return 2
        }
    }

    var osdSpacing: Double {
        switch self {
        case .tvRegular:
            return 8
        case .veryLarge:
            return 8
        case .large:
            return 6
        case .medium:
            return 4
        case .small:
            return 2
        case .smaller:
            return 2
        }
    }

    var displaysTitleLine: Bool {
        self == .tvRegular
    }

    var titleLineFontSize: Double {
        60
    }

    var authorLineFontSize: Double {
        30
    }
}
