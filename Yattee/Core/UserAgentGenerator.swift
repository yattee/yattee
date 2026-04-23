//
//  UserAgentGenerator.swift
//  Yattee
//
//  Generates random User-Agent strings for HTTP requests.
//

import Foundation

/// Generates random User-Agent strings mimicking common browsers and devices.
enum UserAgentGenerator {
    // MARK: - Browser Templates

    /// Chrome on Windows
    private static let chromeWindows: [(version: String, platform: String)] = [
        ("120.0.0.0", "Windows NT 10.0; Win64; x64"),
        ("119.0.0.0", "Windows NT 10.0; Win64; x64"),
        ("121.0.0.0", "Windows NT 10.0; Win64; x64"),
        ("122.0.0.0", "Windows NT 10.0; Win64; x64"),
        ("123.0.0.0", "Windows NT 10.0; Win64; x64"),
    ]

    /// Chrome on macOS
    private static let chromeMac: [(version: String, platform: String)] = [
        ("120.0.0.0", "Macintosh; Intel Mac OS X 10_15_7"),
        ("119.0.0.0", "Macintosh; Intel Mac OS X 10_15_7"),
        ("121.0.0.0", "Macintosh; Intel Mac OS X 14_0"),
        ("122.0.0.0", "Macintosh; Intel Mac OS X 14_1"),
        ("123.0.0.0", "Macintosh; Intel Mac OS X 14_2"),
    ]

    /// Firefox on Windows
    private static let firefoxWindows: [(version: String, platform: String)] = [
        ("121.0", "Windows NT 10.0; Win64; x64"),
        ("120.0", "Windows NT 10.0; Win64; x64"),
        ("122.0", "Windows NT 10.0; Win64; x64"),
        ("123.0", "Windows NT 10.0; Win64; x64"),
    ]

    /// Firefox on macOS
    private static let firefoxMac: [(version: String, platform: String)] = [
        ("121.0", "Macintosh; Intel Mac OS X 10.15"),
        ("120.0", "Macintosh; Intel Mac OS X 10.15"),
        ("122.0", "Macintosh; Intel Mac OS X 14.0"),
        ("123.0", "Macintosh; Intel Mac OS X 14.1"),
    ]

    /// Safari on macOS
    private static let safariMac: [(safariVersion: String, webKitVersion: String, osVersion: String)] = [
        ("17.2", "605.1.15", "10_15_7"),
        ("17.1", "605.1.15", "10_15_7"),
        ("17.3", "605.1.15", "14_2"),
        ("17.0", "605.1.15", "14_0"),
    ]

    /// Edge on Windows
    private static let edgeWindows: [(edgeVersion: String, chromeVersion: String)] = [
        ("120.0.0.0", "120.0.0.0"),
        ("119.0.0.0", "119.0.0.0"),
        ("121.0.0.0", "121.0.0.0"),
        ("122.0.0.0", "122.0.0.0"),
    ]

    // MARK: - Public Methods

    /// Generates a random User-Agent string.
    /// - Returns: A User-Agent string mimicking a common browser.
    static func generateRandom() -> String {
        let browserType = Int.random(in: 0..<10)

        switch browserType {
        case 0...3: // 40% Chrome
            return generateChromeUserAgent()
        case 4...5: // 20% Firefox
            return generateFirefoxUserAgent()
        case 6...7: // 20% Safari
            return generateSafariUserAgent()
        case 8...9: // 20% Edge
            return generateEdgeUserAgent()
        default:
            return generateChromeUserAgent()
        }
    }

    /// Default User-Agent used when no custom value is set.
    static let defaultUserAgent: String = generateRandom()

    // MARK: - Private Methods

    private static func generateChromeUserAgent() -> String {
        let useMac = Bool.random()
        if useMac {
            guard let config = chromeMac.randomElement() else {
                return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            return "Mozilla/5.0 (\(config.platform)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(config.version) Safari/537.36"
        } else {
            guard let config = chromeWindows.randomElement() else {
                return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            return "Mozilla/5.0 (\(config.platform)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(config.version) Safari/537.36"
        }
    }

    private static func generateFirefoxUserAgent() -> String {
        let useMac = Bool.random()
        if useMac {
            guard let config = firefoxMac.randomElement() else {
                return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
            }
            return "Mozilla/5.0 (\(config.platform); rv:\(config.version)) Gecko/20100101 Firefox/\(config.version)"
        } else {
            guard let config = firefoxWindows.randomElement() else {
                return "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
            }
            return "Mozilla/5.0 (\(config.platform); rv:\(config.version)) Gecko/20100101 Firefox/\(config.version)"
        }
    }

    private static func generateSafariUserAgent() -> String {
        guard let config = safariMac.randomElement() else {
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
        }
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(config.osVersion)) AppleWebKit/\(config.webKitVersion) (KHTML, like Gecko) Version/\(config.safariVersion) Safari/\(config.webKitVersion)"
    }

    private static func generateEdgeUserAgent() -> String {
        guard let config = edgeWindows.randomElement() else {
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
        }
        return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(config.chromeVersion) Safari/537.36 Edg/\(config.edgeVersion)"
    }
}
