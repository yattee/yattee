//
//  ChapterParser.swift
//  Yattee
//
//  Parses video chapters from description text.
//

import Foundation

/// Parses video chapters from description text using timestamp detection.
struct ChapterParser: Sendable {
    
    // MARK: - Constants
    
    /// Characters that may prefix a timestamp (to be stripped).
    private static let prefixCharacters = CharacterSet(charactersIn: "▶►•-*→➤")
    
    /// Characters that may separate timestamp from title (to be stripped).
    private static let separatorCharacters = CharacterSet(charactersIn: "-|:–—")
    
    /// Regex pattern for strict timestamp matching.
    /// Matches: M:SS, MM:SS, MMM:SS (for long videos), H:MM:SS, HH:MM:SS
    /// Does not match timestamps in brackets/parentheses (handled by caller).
    private static let timestampPattern = #"^(\d{1,3}):(\d{2})(?::(\d{2}))?$"#
    
    // MARK: - Public API
    
    /// Parses chapters from a video description.
    ///
    /// - Parameters:
    ///   - description: The video description text (may be nil).
    ///   - videoDuration: The video duration in seconds. Must be > 0.
    ///   - introTitle: Title for synthetic intro chapter if first chapter doesn't start at 0:00.
    /// - Returns: Array of chapters, or empty array if parsing fails or no valid chapters found.
    static func parse(
        description: String?,
        videoDuration: TimeInterval,
        introTitle: String = "Intro"
    ) -> [VideoChapter] {
        // Validate inputs
        guard let description, !description.isEmpty else { return [] }
        guard videoDuration > 0 else { return [] }
        
        // Extract raw chapters from description
        let rawChapters = extractChapterBlock(from: description)
        
        // Filter out chapters beyond video duration
        let validChapters = rawChapters.filter { $0.startTime < videoDuration }
        
        // Need minimum 2 chapters
        guard validChapters.count >= 2 else { return [] }
        
        // Sort chronologically
        let sorted = validChapters.sorted { $0.startTime < $1.startTime }
        
        // Merge duplicate timestamps
        let merged = mergeDuplicateTimestamps(sorted)
        
        // Insert synthetic intro if needed
        let withIntro = insertSyntheticIntro(merged, introTitle: introTitle)
        
        // Convert to VideoChapter with end times
        return buildVideoChapters(from: withIntro, videoDuration: videoDuration)
    }
    
    // MARK: - Private Parsing Methods
    
    /// Extracts the first contiguous block of chapter lines from the description.
    private static func extractChapterBlock(from description: String) -> [(startTime: TimeInterval, title: String)] {
        let lines = description.components(separatedBy: .newlines)
        var chapters: [(startTime: TimeInterval, title: String)] = []
        var inBlock = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Empty lines don't break the block
            if trimmed.isEmpty {
                continue
            }
            
            // Try to parse as chapter line
            if let chapter = parseChapterLine(trimmed) {
                inBlock = true
                chapters.append(chapter)
            } else if inBlock {
                // Check if this looks like a timestamp line (even if invalid)
                // Lines that look like they could be timestamps continue the block
                // Lines that clearly aren't timestamps break the block
                if looksLikeTimestampLine(trimmed) {
                    // Invalid timestamp format (brackets, no title, etc.) - skip but continue block
                    continue
                } else {
                    // Clearly not a timestamp line - break the block
                    break
                }
            }
            // If not in block yet and line isn't a chapter, keep looking
        }
        
        return chapters
    }
    
    /// Checks if a line looks like it could be a timestamp line.
    /// Returns true for lines that start with timestamp-like patterns,
    /// even if they would be rejected for other reasons (brackets, no title, etc.).
    private static func looksLikeTimestampLine(_ line: String) -> Bool {
        var working = line
        
        // Strip brackets/parentheses to check what's inside
        if working.hasPrefix("[") || working.hasPrefix("(") {
            working = String(working.dropFirst())
        }
        
        // Strip prefix characters
        working = stripPrefixes(working)
        
        // Check if it starts with a digit (potential timestamp)
        guard let first = working.first, first.isNumber else {
            return false
        }
        
        // Look for timestamp pattern (digits, colons)
        let timestampChars = CharacterSet(charactersIn: "0123456789:")
        let prefix = working.prefix(while: { char in
            char.unicodeScalars.allSatisfy { timestampChars.contains($0) }
        })
        
        // Must have at least one colon to look like a timestamp
        return prefix.contains(":")
    }
    
    /// Parses a single line as a chapter entry.
    ///
    /// - Parameter line: A trimmed line from the description.
    /// - Returns: A tuple of (startTime, title) if valid, nil otherwise.
    private static func parseChapterLine(_ line: String) -> (startTime: TimeInterval, title: String)? {
        var working = line
        
        // Skip if wrapped in brackets or parentheses
        if working.hasPrefix("[") || working.hasPrefix("(") {
            return nil
        }
        
        // Strip prefix characters
        working = stripPrefixes(working)
        
        // Find the timestamp at the start
        guard let (timestamp, remainingAfterTimestamp) = extractLeadingTimestamp(from: working) else {
            return nil
        }
        
        // Strip separators from the title
        let title = stripSeparators(remainingAfterTimestamp).trimmingCharacters(in: .whitespaces)
        
        // Skip if no title
        guard !title.isEmpty else { return nil }
        
        return (timestamp, title)
    }
    
    /// Strips known prefix characters from the start of a string.
    private static func stripPrefixes(_ string: String) -> String {
        var result = string
        while let first = result.unicodeScalars.first,
              prefixCharacters.contains(first) {
            result = String(result.dropFirst())
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
    
    /// Strips known separator characters from the start of a string.
    private static func stripSeparators(_ string: String) -> String {
        var result = string.trimmingCharacters(in: .whitespaces)
        while let first = result.unicodeScalars.first,
              separatorCharacters.contains(first) {
            result = String(result.dropFirst())
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
    
    /// Extracts a timestamp from the start of a string.
    ///
    /// - Parameter string: The string to parse.
    /// - Returns: A tuple of (timestamp in seconds, remaining string after timestamp) if found.
    private static func extractLeadingTimestamp(from string: String) -> (TimeInterval, String)? {
        // Find where the timestamp ends (first space or separator after digits/colons)
        let timestampEndIndex = string.firstIndex { char in
            char == " " || char == "\t" || char == "-" || char == "|" || char == "–" || char == "—"
        } ?? string.endIndex
        
        let potentialTimestamp = String(string[..<timestampEndIndex])
        let remaining = String(string[timestampEndIndex...])
        
        guard let seconds = parseTimestamp(potentialTimestamp) else {
            return nil
        }
        
        return (seconds, remaining)
    }
    
    /// Parses a timestamp string into seconds.
    ///
    /// Supported formats: M:SS, MM:SS, H:MM:SS, HH:MM:SS
    ///
    /// - Parameter timestamp: The timestamp string (e.g., "1:23:45" or "5:30").
    /// - Returns: The time in seconds, or nil if invalid format.
    private static func parseTimestamp(_ timestamp: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return nil
        }
        
        let range = NSRange(timestamp.startIndex..., in: timestamp)
        guard let match = regex.firstMatch(in: timestamp, range: range) else {
            return nil
        }
        
        // Extract capture groups
        guard let firstRange = Range(match.range(at: 1), in: timestamp),
              let secondRange = Range(match.range(at: 2), in: timestamp) else {
            return nil
        }
        
        let first = Int(timestamp[firstRange]) ?? 0
        let second = Int(timestamp[secondRange]) ?? 0
        
        // Check if third group (seconds in H:MM:SS format) exists
        if match.range(at: 3).location != NSNotFound,
           let thirdRange = Range(match.range(at: 3), in: timestamp) {
            // H:MM:SS or HH:MM:SS format
            let hours = first
            let minutes = second
            let seconds = Int(timestamp[thirdRange]) ?? 0
            
            // Validate ranges
            guard minutes < 60, seconds < 60 else { return nil }
            
            return TimeInterval(hours * 3600 + minutes * 60 + seconds)
        } else {
            // M:SS or MM:SS format
            let minutes = first
            let seconds = second
            
            // Validate seconds range
            guard seconds < 60 else { return nil }
            
            return TimeInterval(minutes * 60 + seconds)
        }
    }
    
    // MARK: - Post-Processing Methods
    
    /// Merges chapters with duplicate timestamps by combining their titles.
    private static func mergeDuplicateTimestamps(
        _ chapters: [(startTime: TimeInterval, title: String)]
    ) -> [(startTime: TimeInterval, title: String)] {
        var result: [(startTime: TimeInterval, title: String)] = []
        
        for chapter in chapters {
            if let lastIndex = result.lastIndex(where: { $0.startTime == chapter.startTime }) {
                // Merge with existing chapter at same timestamp
                result[lastIndex].title += " / " + chapter.title
            } else {
                result.append(chapter)
            }
        }
        
        return result
    }
    
    /// Inserts a synthetic intro chapter at 0:00 if the first chapter doesn't start there.
    private static func insertSyntheticIntro(
        _ chapters: [(startTime: TimeInterval, title: String)],
        introTitle: String
    ) -> [(startTime: TimeInterval, title: String)] {
        guard let first = chapters.first, first.startTime > 0 else {
            return chapters
        }
        
        var result = chapters
        result.insert((startTime: 0, title: introTitle), at: 0)
        return result
    }
    
    /// Converts raw chapter data to VideoChapter objects with end times.
    private static func buildVideoChapters(
        from chapters: [(startTime: TimeInterval, title: String)],
        videoDuration: TimeInterval
    ) -> [VideoChapter] {
        return chapters.enumerated().map { index, chapter in
            let endTime: TimeInterval
            if index < chapters.count - 1 {
                endTime = chapters[index + 1].startTime
            } else {
                endTime = videoDuration
            }
            
            return VideoChapter(
                title: chapter.title,
                startTime: chapter.startTime,
                endTime: endTime
            )
        }
    }
}
