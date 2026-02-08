//
//  MediaFile.swift
//  Yattee
//
//  Represents a file or folder from a media source.
//

import Foundation

/// Represents a file or folder from a media source.
struct MediaFile: Identifiable, Hashable, Sendable {
    /// Unique identifier combining source and path.
    var id: String { "\(source.id):\(path)" }

    /// The media source this file belongs to.
    let source: MediaSource

    /// Full path from the source root.
    let path: String

    /// Display name of the file/folder.
    let name: String

    /// Whether this is a directory.
    let isDirectory: Bool
    
    /// Whether this is an SMB share (top-level directory on SMB server).
    let isShare: Bool

    /// File size in bytes (nil for directories).
    let size: Int64?

    /// Last modified date.
    let modifiedDate: Date?

    /// Creation date.
    let createdDate: Date?

    /// MIME type if known.
    let mimeType: String?

    // MARK: - Initialization

    init(
        source: MediaSource,
        path: String,
        name: String,
        isDirectory: Bool,
        isShare: Bool = false,
        size: Int64? = nil,
        modifiedDate: Date? = nil,
        createdDate: Date? = nil,
        mimeType: String? = nil
    ) {
        self.source = source
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.isShare = isShare
        self.size = size
        self.modifiedDate = modifiedDate
        self.createdDate = createdDate
        self.mimeType = mimeType
    }

    // MARK: - Computed Properties

    /// Full URL to this file.
    var url: URL {
        source.url.appendingPathComponent(path)
    }

    /// File extension (lowercase).
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Whether this file is a video.
    var isVideo: Bool {
        guard !isDirectory else { return false }
        return Self.videoExtensions.contains(fileExtension)
    }

    /// Whether this file is an audio file.
    var isAudio: Bool {
        guard !isDirectory else { return false }
        return Self.audioExtensions.contains(fileExtension)
    }

    /// Whether this file is playable media.
    var isPlayable: Bool {
        isVideo || isAudio
    }

    /// Whether this file is a subtitle file.
    var isSubtitle: Bool {
        guard !isDirectory else { return false }
        return Self.subtitleExtensions.contains(fileExtension)
    }

    /// File name without extension.
    var baseName: String {
        (name as NSString).deletingPathExtension
    }

    /// Formatted file size string.
    var formattedSize: String? {
        // Don't show size for directories and shares
        guard !isDirectory, !isShare else { return nil }
        guard let size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// System image name for the file type.
    var systemImage: String {
        if isShare {
            return "externaldrive.fill"
        }
        if isDirectory {
            return "folder.fill"
        }
        if isVideo {
            return "film"
        }
        if isAudio {
            return "music.note"
        }
        if isSubtitle {
            return "captions.bubble"
        }
        return "doc"
    }

    // MARK: - Supported Extensions

    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "wmv",
        "flv", "mpg", "mpeg", "3gp", "3gpp", "ts", "m2ts",
        "vob", "ogv", "rm", "rmvb", "asf", "divx"
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus",
        "wma", "aiff", "alac", "ape"
    ]

    static let subtitleExtensions: Set<String> = [
        "srt", "vtt", "ass", "ssa", "sub"
    ]
}

// MARK: - Conversion to Video/Stream

extension MediaFile {
    /// Provider name for WebDAV media sources (syncs to iCloud).
    static let webdavProvider = "media_source_webdav"

    /// Provider name for local folder media sources (device-specific, never syncs).
    static let localFolderProvider = "media_source_local"

    /// Provider name for SMB media sources (syncs to iCloud).
    static let smbProvider = "media_source_smb"

    /// Returns the appropriate provider name based on source type.
    private var providerName: String {
        switch source.type {
        case .webdav:
            return Self.webdavProvider
        case .localFolder:
            return Self.localFolderProvider
        case .smb:
            return Self.smbProvider
        }
    }

    /// Creates a Video model for playback.
    func toVideo() -> Video {
        Video(
            id: VideoID(
                source: .extracted(extractor: providerName, originalURL: url),
                videoID: id
            ),
            title: (name as NSString).deletingPathExtension,
            description: nil,
            author: Author(id: source.id.uuidString, name: source.name),
            duration: 0, // Unknown until playback
            publishedAt: modifiedDate,
            publishedText: modifiedDate?.formatted(date: .abbreviated, time: .shortened),
            viewCount: nil,
            likeCount: nil,
            thumbnails: [], // No thumbnails for local/WebDAV files
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// Creates a Stream for direct playback.
    /// - Parameter authHeaders: Optional HTTP headers for authentication.
    func toStream(authHeaders: [String: String]? = nil) -> Stream {
        Stream(
            url: url,
            resolution: nil, // Unknown
            format: fileExtension,
            httpHeaders: authHeaders
        )
    }
}

// MARK: - Preview Support

extension MediaFile {
    /// Sample media file for previews.
    static var preview: MediaFile {
        MediaFile(
            source: .webdav(name: "My NAS", url: URL(string: "https://nas.local")!),
            path: "/Movies/Sample Movie.mp4",
            name: "Sample Movie.mp4",
            isDirectory: false,
            size: 1_500_000_000,
            modifiedDate: Date().addingTimeInterval(-86400 * 7)
        )
    }

    /// Sample folder for previews.
    static var folderPreview: MediaFile {
        MediaFile(
            source: .webdav(name: "My NAS", url: URL(string: "https://nas.local")!),
            path: "/Movies",
            name: "Movies",
            isDirectory: true
        )
    }
}

// MARK: - Subtitle Matching

extension MediaFile {
    /// Finds subtitle files in the given list that match this video file.
    /// - Parameter files: List of files to search for matching subtitles.
    /// - Returns: Array of Caption objects for matching subtitle files.
    func findMatchingSubtitles(in files: [MediaFile]) -> [Caption] {
        guard isVideo else { return [] }

        let videoBaseName = baseName
        return files
            .filter { $0.isSubtitle && $0.matchesVideo(baseName: videoBaseName) }
            .compactMap { $0.toCaption(videoBaseName: videoBaseName) }
            .sorted { caption1, caption2 in
                // Sort: exact match (und) first, then alphabetically by language
                if caption1.languageCode == "und" && caption2.languageCode != "und" {
                    return true
                }
                if caption2.languageCode == "und" && caption1.languageCode != "und" {
                    return false
                }
                return caption1.displayName.localizedCaseInsensitiveCompare(caption2.displayName) == .orderedAscending
            }
    }

    /// Checks if this subtitle file matches a video with the given base name.
    private func matchesVideo(baseName videoBaseName: String) -> Bool {
        let subtitleBase = baseName

        // Exact match: video.srt for video.mp4
        if subtitleBase == videoBaseName {
            return true
        }

        // Language suffix with dot: video.en.srt, video.eng.srt, video.English.srt
        if subtitleBase.hasPrefix(videoBaseName + ".") {
            return true
        }

        // Language suffix with underscore: video_en.srt
        if subtitleBase.hasPrefix(videoBaseName + "_") {
            return true
        }

        return false
    }

    /// Converts this subtitle file to a Caption object.
    private func toCaption(videoBaseName: String) -> Caption? {
        guard isSubtitle else { return nil }

        let languageCode = extractLanguageCode(videoBaseName: videoBaseName)
        let displayName: String

        if languageCode == "und" {
            // For exact match without language code, use "Default" as label
            displayName = String(localized: "subtitles.default", defaultValue: "Default")
        } else if let localizedName = Locale.current.localizedString(forLanguageCode: languageCode) {
            displayName = localizedName
        } else {
            displayName = languageCode
        }

        return Caption(
            label: displayName,
            languageCode: languageCode,
            url: url
        )
    }

    /// Extracts the language code from this subtitle filename.
    private func extractLanguageCode(videoBaseName: String) -> String {
        let subtitleBase = baseName

        // Check for pattern: video.en.srt or video_en.srt
        let dotPrefix = videoBaseName + "."
        let underscorePrefix = videoBaseName + "_"

        var suffix: String?
        if subtitleBase.hasPrefix(dotPrefix) {
            suffix = String(subtitleBase.dropFirst(dotPrefix.count))
        } else if subtitleBase.hasPrefix(underscorePrefix) {
            suffix = String(subtitleBase.dropFirst(underscorePrefix.count))
        }

        guard let suffix, !suffix.isEmpty else {
            return "und" // undefined - exact match without language
        }

        // Normalize the language code
        return Self.normalizeLanguageCode(suffix)
    }

    /// Normalizes a language code or name to a standard 2-letter code.
    private static func normalizeLanguageCode(_ input: String) -> String {
        let lowercased = input.lowercased()

        // Map common 3-letter codes to 2-letter
        let threeToTwo: [String: String] = [
            "eng": "en", "deu": "de", "ger": "de", "fra": "fr", "fre": "fr",
            "spa": "es", "ita": "it", "por": "pt", "rus": "ru", "jpn": "ja",
            "kor": "ko", "zho": "zh", "chi": "zh", "ara": "ar", "hin": "hi",
            "pol": "pl", "nld": "nl", "dut": "nl", "swe": "sv", "nor": "no",
            "dan": "da", "fin": "fi", "tur": "tr", "ces": "cs", "cze": "cs",
            "hun": "hu", "ell": "el", "gre": "el", "heb": "he", "tha": "th",
            "vie": "vi", "ukr": "uk", "ron": "ro", "rum": "ro", "bul": "bg",
            "hrv": "hr", "slk": "sk", "slo": "sk", "slv": "sl", "srp": "sr",
            "cat": "ca", "eus": "eu", "baq": "eu", "glg": "gl", "ind": "id",
            "msa": "ms", "may": "ms", "fil": "tl", "tgl": "tl"
        ]

        if let twoLetter = threeToTwo[lowercased] {
            return twoLetter
        }

        // Map common full language names to codes
        let nameToCode: [String: String] = [
            "english": "en", "german": "de", "deutsch": "de", "french": "fr",
            "français": "fr", "francais": "fr", "spanish": "es", "español": "es",
            "espanol": "es", "italian": "it", "italiano": "it", "portuguese": "pt",
            "português": "pt", "portugues": "pt", "russian": "ru", "русский": "ru",
            "japanese": "ja", "日本語": "ja", "korean": "ko", "한국어": "ko",
            "chinese": "zh", "中文": "zh", "arabic": "ar", "العربية": "ar",
            "hindi": "hi", "हिन्दी": "hi", "polish": "pl", "polski": "pl",
            "dutch": "nl", "nederlands": "nl", "swedish": "sv", "svenska": "sv",
            "norwegian": "no", "norsk": "no", "danish": "da", "dansk": "da",
            "finnish": "fi", "suomi": "fi", "turkish": "tr", "türkçe": "tr",
            "czech": "cs", "čeština": "cs", "hungarian": "hu", "magyar": "hu",
            "greek": "el", "ελληνικά": "el", "hebrew": "he", "עברית": "he",
            "thai": "th", "ไทย": "th", "vietnamese": "vi", "tiếng việt": "vi",
            "ukrainian": "uk", "українська": "uk", "romanian": "ro", "română": "ro",
            "bulgarian": "bg", "български": "bg", "croatian": "hr", "hrvatski": "hr",
            "slovak": "sk", "slovenčina": "sk", "slovenian": "sl", "slovenščina": "sl",
            "serbian": "sr", "српски": "sr"
        ]

        if let code = nameToCode[lowercased] {
            return code
        }

        // If it's already a 2-letter code, return it
        if input.count == 2 {
            return lowercased
        }

        // Unknown - return as-is (could be a valid code we don't recognize)
        return lowercased
    }
}
