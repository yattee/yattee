import Defaults

enum SearchDuration: String, CaseIterable, Identifiable, DefaultsSerializable {
    case short, long

    var id: SearchDuration.RawValue {
        rawValue
    }

    var name: String {
        rawValue.capitalized
    }
}
