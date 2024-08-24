// swiftlint:disable switch_case_on_newline
import Defaults

enum Country: String, CaseIterable, Identifiable, Hashable, Defaults.Serializable {
    var id: String {
        rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    case dz = "DZ"
    case ar = "AR"
    case au = "AU"
    case at = "AT"
    case az = "AZ"
    case bh = "BH"
    case bd = "BD"
    case by = "BY"
    case be = "BE"
    case bo = "BO"
    case ba = "BA"
    case br = "BR"
    case bg = "BG"
    case ca = "CA"
    case cl = "CL"
    case co = "CO"
    case cr = "CR"
    case hr = "HR"
    case cy = "CY"
    case cz = "CZ"
    case dk = "DK"
    case `do` = "DO"
    case ec = "EC"
    case eg = "EG"
    case sv = "SV"
    case ee = "EE"
    case fi = "FI"
    case fr = "FR"
    case ge = "GE"
    case de = "DE"
    case gh = "GH"
    case gr = "GR"
    case gt = "GT"
    case hn = "HN"
    case hk = "HK"
    case hu = "HU"
    case `is` = "IS"
    case `in` = "IN"
    case id = "ID"
    case iq = "IQ"
    case ie = "IE"
    case il = "IL"
    case it = "IT"
    case jm = "JM"
    case jp = "JP"
    case jo = "JO"
    case kz = "KZ"
    case ke = "KE"
    case kr = "KR"
    case kw = "KW"
    case lv = "LV"
    case lb = "LB"
    case ly = "LY"
    case li = "LI"
    case lt = "LT"
    case lu = "LU"
    case mk = "MK"
    case my = "MY"
    case mt = "MT"
    case mx = "MX"
    case me = "ME"
    case ma = "MA"
    case np = "NP"
    case nl = "NL"
    case nz = "NZ"
    case ni = "NI"
    case ng = "NG"
    case no = "NO"
    case om = "OM"
    case pk = "PK"
    case pa = "PA"
    case pg = "PG"
    case py = "PY"
    case pe = "PE"
    case ph = "PH"
    case pl = "PL"
    case pt = "PT"
    case pr = "PR"
    case qa = "QA"
    case ro = "RO"
    case ru = "RU"
    case sa = "SA"
    case sn = "SN"
    case rs = "RS"
    case sg = "SG"
    case sk = "SK"
    case si = "SI"
    case za = "ZA"
    case es = "ES"
    case lk = "LK"
    case se = "SE"
    case ch = "CH"
    case tw = "TW"
    case tz = "TZ"
    case th = "TH"
    case tn = "TN"
    case tr = "TR"
    case ug = "UG"
    case ua = "UA"
    case ae = "AE"
    case gb = "GB"
    case us = "US"
    case uy = "UY"
    case ve = "VE"
    case vn = "VN"
    case vi = "VI"
    case ye = "YE"
    case zw = "ZW"
}

extension Country {
    var name: String {
        switch self {
        case .dz: return "Algeria"
        case .ar: return "Argentina"
        case .au: return "Australia"
        case .at: return "Austria"
        case .az: return "Azerbaijan"
        case .bh: return "Bahrain"
        case .bd: return "Bangladesh"
        case .by: return "Belarus"
        case .be: return "Belgium"
        case .bo: return "Bolivia (Plurinational State of)"
        case .ba: return "Bosnia and Herzegovina"
        case .br: return "Brazil"
        case .bg: return "Bulgaria"
        case .ca: return "Canada"
        case .cl: return "Chile"
        case .co: return "Colombia"
        case .cr: return "Costa Rica"
        case .hr: return "Croatia"
        case .cy: return "Cyprus"
        case .cz: return "Czechia"
        case .dk: return "Denmark"
        case .do: return "Dominican Republic"
        case .ec: return "Ecuador"
        case .eg: return "Egypt"
        case .sv: return "El Salvador"
        case .ee: return "Estonia"
        case .fi: return "Finland"
        case .fr: return "France"
        case .ge: return "Georgia"
        case .de: return "Germany"
        case .gh: return "Ghana"
        case .gr: return "Greece"
        case .gt: return "Guatemala"
        case .hn: return "Honduras"
        case .hk: return "Hong Kong"
        case .hu: return "Hungary"
        case .is: return "Iceland"
        case .in: return "India"
        case .id: return "Indonesia"
        case .iq: return "Iraq"
        case .ie: return "Ireland"
        case .il: return "Israel"
        case .it: return "Italy"
        case .jm: return "Jamaica"
        case .jp: return "Japan"
        case .jo: return "Jordan"
        case .kz: return "Kazakhstan"
        case .ke: return "Kenya"
        case .kr: return "Korea (Republic of)"
        case .kw: return "Kuwait"
        case .lv: return "Latvia"
        case .lb: return "Lebanon"
        case .ly: return "Libya"
        case .li: return "Liechtenstein"
        case .lt: return "Lithuania"
        case .lu: return "Luxembourg"
        case .mk: return "Macedonia (the former Yugoslav Republic of)"
        case .my: return "Malaysia"
        case .mt: return "Malta"
        case .mx: return "Mexico"
        case .me: return "Montenegro"
        case .ma: return "Morocco"
        case .np: return "Nepal"
        case .nl: return "Netherlands"
        case .nz: return "New Zealand"
        case .ni: return "Nicaragua"
        case .ng: return "Nigeria"
        case .no: return "Norway"
        case .om: return "Oman"
        case .pk: return "Pakistan"
        case .pa: return "Panama"
        case .pg: return "Papua New Guinea"
        case .py: return "Paraguay"
        case .pe: return "Peru"
        case .ph: return "Philippines"
        case .pl: return "Poland"
        case .pt: return "Portugal"
        case .pr: return "Puerto Rico"
        case .qa: return "Qatar"
        case .ro: return "Romania"
        case .ru: return "Russian Federation"
        case .sa: return "Saudi Arabia"
        case .sn: return "Senegal"
        case .rs: return "Serbia"
        case .sg: return "Singapore"
        case .sk: return "Slovakia"
        case .si: return "Slovenia"
        case .za: return "South Africa"
        case .es: return "Spain"
        case .lk: return "Sri Lanka"
        case .se: return "Sweden"
        case .ch: return "Switzerland"
        case .tw: return "Taiwan"
        case .tz: return "Tanzania, United Republic of"
        case .th: return "Thailand"
        case .tn: return "Tunisia"
        case .tr: return "Turkey"
        case .ug: return "Uganda"
        case .ua: return "Ukraine"
        case .ae: return "United Arab Emirates"
        case .gb: return "United Kingdom of Great Britain and Northern Ireland"
        case .us: return "United States of America"
        case .uy: return "Uruguay"
        case .ve: return "Venezuela (Bolivarian Republic of)"
        case .vn: return "Viet Nam"
        case .vi: return "Virgin Islands (U.S.)"
        case .ye: return "Yemen"
        case .zw: return "Zimbabwe"
        }
    }

    // swiftlint:enable switch_case_on_newline

    var flag: String {
        let unicodeScalars = rawValue
            .unicodeScalars
            .map { $0.value + 0x1F1E6 - 65 }
            .compactMap(UnicodeScalar.init)
        var result = ""
        result.unicodeScalars.append(contentsOf: unicodeScalars)
        return result
    }

    static func search(_ query: String) -> [Country] {
        if let country = searchByCode(query) {
            return [country]
        }

        let countries = filteredCountries { stringFolding($0) == stringFolding(query) }

        return countries.isEmpty ? searchByPartialName(query) : countries
    }

    static func searchByCode(_ code: String) -> Country? {
        Country(rawValue: code.uppercased())
    }

    static func searchByPartialName(_ name: String) -> [Country] {
        guard !name.isEmpty else {
            return []
        }

        return filteredCountries { stringFolding($0).contains(stringFolding(name)) }
    }

    private static func stringFolding(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func filteredCountries(_ predicate: (String) -> Bool) -> [Country] {
        Country.allCases
            .map(\.name)
            .filter(predicate)
            .compactMap { string in Country.allCases.first { $0.name == string } }
    }
}
