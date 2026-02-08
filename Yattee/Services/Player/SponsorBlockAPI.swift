//
//  SponsorBlockAPI.swift
//  Yattee
//
//  SponsorBlock API client for fetching video segments.
//

import Foundation

/// Action type for a segment.
enum SponsorBlockActionType: String, Codable, Sendable {
    case skip = "skip"
    case mute = "mute"
    case chapter = "chapter"
    case full = "full"
    case poi = "poi"
}

/// A segment from SponsorBlock.
struct SponsorBlockSegment: Codable, Identifiable, Sendable {
    let uuid: String
    let category: SponsorBlockCategory
    let actionType: SponsorBlockActionType
    let segment: [Double]
    let videoDuration: Double?
    let locked: Int?
    let votes: Int?
    let segmentDescription: String?

    var id: String { uuid }

    /// Start time in seconds.
    var startTime: Double {
        segment.first ?? 0
    }

    /// End time in seconds.
    var endTime: Double {
        segment.last ?? 0
    }

    /// Duration of the segment.
    var duration: Double {
        endTime - startTime
    }

    /// Whether this is a point of interest (single timestamp).
    var isPointOfInterest: Bool {
        actionType == .poi || startTime == endTime
    }

    private enum CodingKeys: String, CodingKey {
        case uuid = "UUID"
        case category
        case actionType
        case segment
        case videoDuration
        case locked
        case votes
        case segmentDescription = "description"
    }
}

/// SponsorBlock API client.
actor SponsorBlockAPI {
    private let httpClient: HTTPClient
    private var baseURL: URL

    /// Cache for segments by video ID.
    private var segmentCache: [String: [SponsorBlockSegment]] = [:]

    /// Default SponsorBlock API URL.
    private static let defaultAPIURL = URL(string: "https://sponsor.ajay.app")!

    init(httpClient: HTTPClient, baseURL: URL? = nil) {
        self.httpClient = httpClient
        self.baseURL = baseURL ?? Self.defaultAPIURL
    }

    /// Updates the base URL for API requests.
    /// Clears the segment cache when URL changes.
    func setBaseURL(_ url: URL) {
        if baseURL != url {
            baseURL = url
            segmentCache.removeAll()
        }
    }

    /// Fetches segments for a YouTube video.
    func segments(
        for videoID: String,
        categories: Set<SponsorBlockCategory> = Set(SponsorBlockCategory.allCases)
    ) async throws -> [SponsorBlockSegment] {
        // Check cache first
        if let cached = segmentCache[videoID] {
            return cached.filter { categories.contains($0.category) }
        }

        let categoryParams = categories.map { $0.rawValue }
        let categoriesJSON = try JSONEncoder().encode(categoryParams)
        guard let categoriesString = String(data: categoriesJSON, encoding: .utf8) else {
            throw APIError.invalidRequest
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/api/skipSegments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoID),
            URLQueryItem(name: "categories", value: categoriesString)
        ]

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let data = try await httpClient.performRaw(request)
            let decoder = JSONDecoder()
            let segments = try decoder.decode([SponsorBlockSegment].self, from: data)

            // Cache the result
            segmentCache[videoID] = segments

            Task { @MainActor in
                LoggingService.shared.logPlayer("SponsorBlock: \(segments.count) segments", details: "Video: \(videoID)")
            }
            return segments.filter { categories.contains($0.category) }
        } catch let error as DecodingError {
            Task { @MainActor in
                LoggingService.shared.logPlayerError("SponsorBlock decode error", error: error)
            }
            throw APIError.decodingError(error)
        } catch let error as APIError {
            // 404 means no segments exist for this video
            if case .notFound = error {
                segmentCache[videoID] = []
                return []
            }
            throw error
        }
    }
}

// MARK: - Segment Filtering

extension Array where Element == SponsorBlockSegment {
    /// Filters to only skippable segments.
    func skippable() -> [SponsorBlockSegment] {
        filter { $0.actionType == .skip }
    }

    /// Filters to only segments in the given categories.
    func inCategories(_ categories: Set<SponsorBlockCategory>) -> [SponsorBlockSegment] {
        filter { categories.contains($0.category) }
    }

    /// Finds a segment containing the given time.
    func segment(at time: Double) -> SponsorBlockSegment? {
        first { time >= $0.startTime && time < $0.endTime }
    }

    /// Finds the next segment after the given time.
    func nextSegment(after time: Double) -> SponsorBlockSegment? {
        filter { $0.startTime > time }
            .sorted { $0.startTime < $1.startTime }
            .first
    }
}

// MARK: - Chapter Extraction

extension Array where Element == SponsorBlockSegment {
    /// Extracts chapter segments and converts them to VideoChapter array.
    ///
    /// SponsorBlock chapters have:
    /// - `actionType == .chapter`
    /// - `segment[0]` = startTime
    /// - `segmentDescription` = chapter title
    ///
    /// - Parameter videoDuration: The video duration for calculating end times.
    /// - Returns: Array of VideoChapter, or empty if no valid chapters found.
    func extractChapters(videoDuration: TimeInterval) -> [VideoChapter] {
        // Filter to chapter segments only
        let chapterSegments = filter { $0.actionType == .chapter }
        
        // Need at least 2 chapters
        guard chapterSegments.count >= 2 else { return [] }
        
        // Sort by start time
        let sorted = chapterSegments.sorted { $0.startTime < $1.startTime }
        
        // Convert to VideoChapter with proper end times
        return sorted.enumerated().map { index, segment in
            let title = segment.segmentDescription ?? "Chapter \(index + 1)"
            let startTime = TimeInterval(segment.startTime)
            let endTime: TimeInterval
            
            if index < sorted.count - 1 {
                endTime = TimeInterval(sorted[index + 1].startTime)
            } else {
                endTime = videoDuration
            }
            
            return VideoChapter(
                title: title,
                startTime: startTime,
                endTime: endTime
            )
        }
    }
}
