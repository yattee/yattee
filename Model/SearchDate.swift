import Defaults

enum SearchDate: String, CaseIterable, Identifiable, DefaultsSerializable {
    case hour, today, week, month, year

    var id: SearchDate.RawValue {
        rawValue
    }

    var name: String {
        rawValue.capitalized
    }
}
