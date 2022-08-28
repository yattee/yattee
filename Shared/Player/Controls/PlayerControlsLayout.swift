import Defaults
import Foundation

enum PlayerControlsLayout: String, CaseIterable, Defaults.Serializable {
    case veryLarge
    case large
    case medium
    case small
    case smaller

    var description: String {
        switch self {
        case .veryLarge:
            return "Very Large"
        default:
            return rawValue.capitalized
        }
    }

    var buttonsSpacing: Double {
        switch self {
        case .veryLarge:
            return 40
        case .large:
            return 30
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

    var thumbSize: Double {
        switch self {
        case .veryLarge:
            return 35
        case .large:
            return 30
        case .medium:
            return 20
        case .small:
            return 15
        case .smaller:
            return 13
        }
    }

    var timeFontSize: Double {
        switch self {
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
        switch self {
        case .veryLarge:
            return 16
        case .large:
            return 14
        case .medium:
            return 9
        case .small:
            return 6
        case .smaller:
            return 2
        }
    }

    var timelineHeight: Double {
        switch self {
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
}
