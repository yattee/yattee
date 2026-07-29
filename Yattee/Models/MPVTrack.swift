//
//  MPVTrack.swift
//  Yattee
//
//  Model representing one entry of mpv's `track-list` property.
//

import Foundation

/// A single track reported by mpv's `track-list` property (embedded or external).
struct MPVTrack: Equatable, Sendable, Identifiable, Decodable {
    enum TrackType: String, Decodable, Sendable {
        case video
        case audio
        case sub
    }

    /// mpv track id — unique only within a track type.
    let trackID: Int
    let type: TrackType
    let title: String?
    let lang: String?
    let isDefault: Bool
    let isForced: Bool
    /// True for tracks loaded via `sub-add`/`audio-add` (external files).
    let isExternal: Bool
    /// Whether mpv currently plays this track.
    let isSelected: Bool
    /// Cover-art pseudo video tracks.
    let isAlbumArt: Bool
    let codec: String?
    let channelCount: Int?
    let sampleRate: Int?

    /// Identifiable across types — mpv ids collide between audio/sub/video.
    var id: String { "\(type.rawValue):\(trackID)" }

    private enum CodingKeys: String, CodingKey {
        case trackID = "id"
        case type
        case title
        case lang
        case isDefault = "default"
        case isForced = "forced"
        case isExternal = "external"
        case isSelected = "selected"
        case isAlbumArt = "albumart"
        case codec
        case channelCount = "demux-channel-count"
        case sampleRate = "demux-samplerate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decode(Int.self, forKey: .trackID)
        type = try container.decode(TrackType.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
        isExternal = try container.decodeIfPresent(Bool.self, forKey: .isExternal) ?? false
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        isAlbumArt = try container.decodeIfPresent(Bool.self, forKey: .isAlbumArt) ?? false
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount)
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate)
    }

    init(
        trackID: Int,
        type: TrackType,
        title: String? = nil,
        lang: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isExternal: Bool = false,
        isSelected: Bool = false,
        isAlbumArt: Bool = false,
        codec: String? = nil,
        channelCount: Int? = nil,
        sampleRate: Int? = nil
    ) {
        self.trackID = trackID
        self.type = type
        self.title = title
        self.lang = lang
        self.isDefault = isDefault
        self.isForced = isForced
        self.isExternal = isExternal
        self.isSelected = isSelected
        self.isAlbumArt = isAlbumArt
        self.codec = codec
        self.channelCount = channelCount
        self.sampleRate = sampleRate
    }

    /// Base language code normalized to the 2-letter form when possible, so
    /// Matroska 3-letter codes ("eng") match preference values ("en").
    var baseLanguageCode: String? {
        guard let lang, !lang.isEmpty, lang != "und" else { return nil }
        var code = lang.lowercased()
        if let hyphenIndex = code.firstIndex(of: "-") {
            code = String(code[..<hyphenIndex])
        }
        guard code.count == 3 else { return code }
        // ISO 639-2 -> 639-1 where a 2-letter code exists ("eng" -> "en").
        return Locale.LanguageCode(code).identifier(.alpha2) ?? code
    }

    /// "Director's Commentary", "English", or a numbered fallback.
    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        if let baseLanguageCode,
           let localized = Locale.current.localizedString(forLanguageCode: baseLanguageCode) {
            return localized
        }
        return String(localized: "player.track.number \(trackID)")
    }

    /// Whether this track's language matches a user preference code like "en".
    func matchesLanguage(_ preferredCode: String?) -> Bool {
        guard let preferredCode, !preferredCode.isEmpty,
              let baseLanguageCode else { return false }
        var preferred = preferredCode.lowercased()
        if let hyphenIndex = preferred.firstIndex(of: "-") {
            preferred = String(preferred[..<hyphenIndex])
        }
        if preferred.count == 3 {
            preferred = Locale.LanguageCode(preferred).identifier(.alpha2) ?? preferred
        }
        return preferred == baseLanguageCode
    }

    /// Secondary detail line for advanced mode, e.g. "eac3 · 6ch · 48 kHz".
    var detailText: String? {
        var parts: [String] = []
        if let codec, !codec.isEmpty {
            parts.append(codec)
        }
        if let channelCount {
            parts.append("\(channelCount)ch")
        }
        if let sampleRate {
            parts.append("\(sampleRate / 1000) kHz")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
