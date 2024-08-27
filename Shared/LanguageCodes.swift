enum LanguageCodes: String, CaseIterable {
    case Afrikaans = "af"
    case Arabic = "ar"
    case Azerbaijani = "az"
    case Bengali = "bn"
    case Catalan = "ca"
    case Czech = "cs"
    case Welsh = "cy"
    case Danish = "da"
    case German = "de"
    case Greek = "el"
    case English = "en"
    case English_GB = "en-GB"
    case Spanish = "es"
    case Persian = "fa"
    case Finnish = "fi"
    case Filipino = "fil"
    case French = "fr"
    case Irish = "ga"
    case Hebrew = "he"
    case Hindi = "hi"
    case Hungarian = "hu"
    case Indonesian = "id"
    case Italian = "it"
    case Japanese = "ja"
    case Javanese = "jv"
    case Korean = "ko"
    case Lithuanian = "lt"
    case Malay = "ms"
    case Maltese = "mt"
    case Dutch = "nl"
    case Norwegian = "no"
    case Polish = "pl"
    case Portuguese = "pt"
    case Romanian = "ro"
    case Russian = "ru"
    case Slovak = "sk"
    case Slovene = "sl"
    case Swedish = "sv"
    case Swahili = "sw"
    case Thai = "th"
    case Tagalog = "tl"
    case Turkish = "tr"
    case Ukrainian = "uk"
    case Urdu = "ur"
    case Uzbek = "uz"
    case Vietnamese = "vi"
    case Xhosa = "xh"
    case Chinese = "zh"
    case Chinese_Hans = "zh-Hans"
    case Zulu = "zu"

    var description: String {
        switch self {
        case .Afrikaans:
            return "Afrikaans"
        case .Arabic:
            return "Arabic"
        case .Azerbaijani:
            return "Azerbaijani"
        case .Bengali:
            return "Bengali"
        case .Catalan:
            return "Catalan"
        case .Czech:
            return "Czech"
        case .Welsh:
            return "Welsh"
        case .Danish:
            return "Danish"
        case .German:
            return "German"
        case .Greek:
            return "Greek"
        case .English:
            return "English"
        case .English_GB:
            return "English (United Kingdom)"
        case .Spanish:
            return "Spanish"
        case .Persian:
            return "Persian"
        case .Finnish:
            return "Finnish"
        case .Filipino:
            return "Filipino"
        case .French:
            return "French"
        case .Irish:
            return "Irish"
        case .Hebrew:
            return "Hebrew"
        case .Hindi:
            return "Hindi"
        case .Hungarian:
            return "Hungarian"
        case .Indonesian:
            return "Indonesian"
        case .Italian:
            return "Italian"
        case .Japanese:
            return "Japanese"
        case .Javanese:
            return "Javanese"
        case .Korean:
            return "Korean"
        case .Lithuanian:
            return "Lithuanian"
        case .Malay:
            return "Malay"
        case .Maltese:
            return "Maltese"
        case .Dutch:
            return "Dutch"
        case .Norwegian:
            return "Norwegian"
        case .Polish:
            return "Polish"
        case .Portuguese:
            return "Portuguese"
        case .Romanian:
            return "Romanian"
        case .Russian:
            return "Russian"
        case .Slovak:
            return "Slovak"
        case .Slovene:
            return "Slovene"
        case .Swedish:
            return "Swedish"
        case .Swahili:
            return "Swahili"
        case .Thai:
            return "Thai"
        case .Tagalog:
            return "Tagalog"
        case .Turkish:
            return "Turkish"
        case .Ukrainian:
            return "Ukrainian"
        case .Urdu:
            return "Urdu"
        case .Uzbek:
            return "Uzbek"
        case .Vietnamese:
            return "Vietnamese"
        case .Xhosa:
            return "Xhosa"
        case .Chinese:
            return "Chinese"
        case .Chinese_Hans:
            return "Chinese (Simplified)"
        case .Zulu:
            return "Zulu"
        }
    }

    static func languageName(for code: String) -> String {
        return Self(rawValue: code)?.description ?? "Unknown"
    }
}
