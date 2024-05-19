import Foundation
import Logging

enum URLTester {
    private static let hlsMediaPrefix = "#EXT-X-MEDIA:"
    private static let hlsInfPrefix = "#EXTINF:"
    private static let uriRegex = "(?<=URI=\")(.*?)(?=\")"

    static func testURLResponse(url: URL, range: String, isHLS: Bool, completion: @escaping (Int) -> Void) {
        if isHLS {
            parseAndTestHLSManifest(manifestUrl: url, range: range, completion: completion)
        } else {
            httpRequest(url: url, range: range) { statusCode, _ in
                completion(statusCode)
            }
        }
    }

    private static func httpRequest(url: URL, range: String, completion: @escaping (Int, URLSessionDataTask?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("bytes=\(range)", forHTTPHeaderField: "Range")
        request.setValue(UserAgentManager.shared.userAgent, forHTTPHeaderField: "User-Agent")

        var dataTask: URLSessionDataTask?
        dataTask = URLSession.shared.dataTask(with: request) { _, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? HTTPStatus.Forbidden
            Logger(label: "stream.yattee.httpRequest").info("URL: \(url) | Status Code: \(statusCode)")
            completion(statusCode, dataTask)
        }
        dataTask?.resume()
    }

    static func parseAndTestHLSManifest(manifestUrl: URL, range: String, completion: @escaping (Int) -> Void) {
        recursivelyParseManifest(manifestUrl: manifestUrl) { allURLs in
            if let url = allURLs.randomElement() {
                httpRequest(url: url, range: range) { statusCode, _ in
                    completion(statusCode)
                }
            } else {
                completion(HTTPStatus.NotFound)
            }
        }
    }

    private static func recursivelyParseManifest(manifestUrl: URL, fullyParsed: @escaping ([URL]) -> Void) {
        parseHLSManifest(manifestUrl: manifestUrl) { urls in
            var allURLs = [URL]()
            let group = DispatchGroup()
            for url in urls {
                if url.pathExtension == "m3u8" {
                    group.enter()
                    recursivelyParseManifest(manifestUrl: url) { subUrls in
                        allURLs += subUrls
                        group.leave()
                    }
                } else {
                    allURLs.append(url)
                }
            }
            group.notify(queue: .main) {
                fullyParsed(allURLs)
            }
        }
    }

    private static func parseHLSManifest(manifestUrl: URL, completion: @escaping ([URL]) -> Void) {
        URLSession.shared.dataTask(with: manifestUrl) { data, _, _ in
            // swiftlint:disable:next shorthand_optional_binding
            guard let data = data else {
                Logger(label: "stream.yattee.httpRequest").error("Data is nil")
                completion([])
                return
            }

            // swiftlint:disable:next non_optional_string_data_conversion
            guard let manifest = String(data: data, encoding: .utf8), !manifest.isEmpty else {
                Logger(label: "stream.yattee.httpRequest").error("Cannot read or empty HLS manifest")
                completion([])
                return
            }

            let lines = manifest.split(separator: "\n")
            var mediaURLs: [URL] = []

            for index in 0 ..< lines.count {
                let lineString = String(lines[index])

                if lineString.hasPrefix(hlsMediaPrefix),
                   let uriRange = lineString.range(of: uriRegex, options: .regularExpression)
                {
                    let uri = lineString[uriRange]
                    if let url = URL(string: String(uri)) {
                        mediaURLs.append(url)
                    }
                } else if lineString.hasPrefix(hlsInfPrefix), index < lines.count - 1 {
                    let possibleURL = String(lines[index + 1])
                    let baseURL = manifestUrl.deletingLastPathComponent()
                    if let relativeURL = URL(string: possibleURL, relativeTo: baseURL),
                       relativeURL.scheme != nil
                    {
                        mediaURLs.append(relativeURL)
                    }
                }
            }
            completion(mediaURLs)
        }
        .resume()
    }
}
