//
//  SubscriptionImportExport.swift
//  Yattee
//
//  Service for importing and exporting subscriptions in various formats.
//

import Foundation

// MARK: - Import/Export Errors

enum SubscriptionImportError: LocalizedError {
    case invalidData
    case emptyFile
    case noValidSubscriptions
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return String(localized: "subscriptions.import.error.invalidData")
        case .emptyFile:
            return String(localized: "subscriptions.import.error.emptyFile")
        case .noValidSubscriptions:
            return String(localized: "subscriptions.import.error.noValidSubscriptions")
        case .parsingFailed(let details):
            return String(localized: "subscriptions.import.error.parsingFailed \(details)")
        }
    }
}

// MARK: - Export Format

enum SubscriptionExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case opml = "OPML"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .opml: return "opml"
        }
    }

    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .opml: return "text/x-opml"
        }
    }
}

// MARK: - Import Result

struct SubscriptionImportResult {
    let channels: [(channelID: String, name: String)]
    let format: String
}

// MARK: - Service

enum SubscriptionImportExport {

    // MARK: - Format Detection

    static func detectFormat(_ data: Data) -> String? {
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<opml") {
            return "opml"
        } else if trimmed.contains("Channel Id") || trimmed.contains("channel_id") {
            return "csv"
        }
        return nil
    }

    // MARK: - YouTube CSV Import

    /// Parses YouTube subscription export CSV format.
    /// Expected format: Channel Id,Channel Url,Channel Title
    static func parseYouTubeCSV(_ data: Data) throws -> [(channelID: String, name: String)] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw SubscriptionImportError.invalidData
        }

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw SubscriptionImportError.emptyFile
        }

        var results: [(channelID: String, name: String)] = []
        var startIndex = 0

        // Check for header row
        if let firstLine = lines.first?.lowercased(),
           firstLine.contains("channel id") || firstLine.contains("channel_id") {
            startIndex = 1
        }

        for i in startIndex..<lines.count {
            let line = lines[i]
            let columns = parseCSVLine(line)

            // YouTube format: Channel Id, Channel Url, Channel Title
            guard columns.count >= 3 else { continue }

            let channelID = columns[0].trimmingCharacters(in: .whitespaces)
            let name = columns[2].trimmingCharacters(in: .whitespaces)

            // Validate channel ID format (should start with UC for YouTube)
            guard !channelID.isEmpty, !name.isEmpty else { continue }

            results.append((channelID: channelID, name: name))
        }

        guard !results.isEmpty else {
            throw SubscriptionImportError.noValidSubscriptions
        }

        LoggingService.shared.logSubscriptions("Parsed \(results.count) subscriptions from YouTube CSV")
        return results
    }

    /// Parses a CSV line handling quoted fields
    private static func parseCSVLine(_ line: String) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                results.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        results.append(current)

        return results
    }

    // MARK: - OPML Import

    /// Parses OPML subscription format.
    static func parseOPML(_ data: Data) throws -> [(channelID: String, name: String)] {
        let parser = OPMLParser()
        let results = try parser.parse(data)

        guard !results.isEmpty else {
            throw SubscriptionImportError.noValidSubscriptions
        }

        LoggingService.shared.logSubscriptions("Parsed \(results.count) subscriptions from OPML")
        return results
    }

    // MARK: - Auto-detect and Parse

    /// Attempts to parse the data by auto-detecting the format.
    static func parseAuto(_ data: Data) throws -> SubscriptionImportResult {
        guard let format = detectFormat(data) else {
            // Try CSV first, then OPML
            if let results = try? parseYouTubeCSV(data), !results.isEmpty {
                return SubscriptionImportResult(channels: results, format: "CSV")
            }
            if let results = try? parseOPML(data), !results.isEmpty {
                return SubscriptionImportResult(channels: results, format: "OPML")
            }
            throw SubscriptionImportError.invalidData
        }

        switch format {
        case "csv":
            return SubscriptionImportResult(channels: try parseYouTubeCSV(data), format: "CSV")
        case "opml":
            return SubscriptionImportResult(channels: try parseOPML(data), format: "OPML")
        default:
            throw SubscriptionImportError.invalidData
        }
    }

    // MARK: - JSON Export

    /// Exports subscriptions to JSON format using SubscriptionExport structure.
    static func exportToJSON(_ subscriptions: [Subscription]) -> Data? {
        let exports = subscriptions.map { SubscriptionExport(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            return try encoder.encode(exports)
        } catch {
            LoggingService.shared.logSubscriptionsError("Failed to encode subscriptions to JSON", error: error)
            return nil
        }
    }

    // MARK: - OPML Export

    /// Exports subscriptions to OPML format compatible with RSS readers.
    static func exportToOPML(_ subscriptions: [Subscription]) -> Data? {
        let dateFormatter = ISO8601DateFormatter()
        let dateCreated = dateFormatter.string(from: Date())

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
          <head>
            <title>Yattee Subscriptions</title>
            <dateCreated>\(dateCreated)</dateCreated>
          </head>
          <body>
            <outline text="YouTube Subscriptions" title="YouTube Subscriptions">

        """

        for subscription in subscriptions {
            let name = escapeXML(subscription.name)
            let feedURL = "https://www.youtube.com/feeds/videos.xml?channel_id=\(subscription.channelID)"
            xml += """
                  <outline text="\(name)" title="\(name)" type="rss" xmlUrl="\(feedURL)"/>

            """
        }

        xml += """
            </outline>
          </body>
        </opml>
        """

        return xml.data(using: .utf8)
    }

    /// Escapes special XML characters
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Generates a filename for export
    static func generateExportFilename(format: SubscriptionExportFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return "yattee-subscriptions-\(dateString).\(format.fileExtension)"
    }
}

// MARK: - OPML Parser

private class OPMLParser: NSObject, XMLParserDelegate {
    private var results: [(channelID: String, name: String)] = []
    private var parseError: Error?

    func parse(_ data: Data) throws -> [(channelID: String, name: String)] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let error = parseError {
            throw error
        }

        return results
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName.lowercased() == "outline" else { return }

        // Try to extract channel ID from xmlUrl
        if let xmlUrl = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"],
           let channelID = extractChannelID(from: xmlUrl) {
            let name = attributeDict["text"] ?? attributeDict["title"] ?? "Unknown Channel"
            results.append((channelID: channelID, name: name))
        }
    }

    private func extractChannelID(from urlString: String) -> String? {
        // Handle YouTube RSS feed URL: youtube.com/feeds/videos.xml?channel_id=UCXXX
        if urlString.contains("channel_id=") {
            if let range = urlString.range(of: "channel_id=") {
                let afterParam = urlString[range.upperBound...]
                let channelID = afterParam.prefix(while: { $0 != "&" && $0 != " " })
                if !channelID.isEmpty {
                    return String(channelID)
                }
            }
        }

        // Handle YouTube channel URL: youtube.com/channel/UCXXX
        if urlString.contains("/channel/") {
            if let range = urlString.range(of: "/channel/") {
                let afterChannel = urlString[range.upperBound...]
                let channelID = afterChannel.prefix(while: { $0 != "/" && $0 != "?" && $0 != " " })
                if !channelID.isEmpty {
                    return String(channelID)
                }
            }
        }

        return nil
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = SubscriptionImportError.parsingFailed(parseError.localizedDescription)
    }
}
