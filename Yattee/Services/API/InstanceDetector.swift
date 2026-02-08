//
//  InstanceDetector.swift
//  Yattee
//
//  Automatically detects backend instance type by probing API endpoints.
//

import Foundation

/// Errors that can occur during instance detection.
enum DetectionError: Error, Sendable {
    case sslCertificateError
    case networkError(String)
    case unknownType
    case invalidURL
    case timeout

    var localizedDescription: String {
        switch self {
        case .sslCertificateError:
            return String(localized: "sources.error.sslCertificate")
        case .networkError(let message):
            return message
        case .unknownType:
            return String(localized: "sources.error.couldNotDetect")
        case .invalidURL:
            return String(localized: "sources.validation.invalidURL")
        case .timeout:
            return String(localized: "sources.error.timeout")
        }
    }
}

/// Result of instance detection including type and authentication requirements.
struct InstanceDetectionResult: Sendable {
    let type: InstanceType
    /// Whether this instance requires authentication (Basic Auth for Yattee Server).
    let requiresAuth: Bool

    init(type: InstanceType, requiresAuth: Bool = false) {
        self.type = type
        self.requiresAuth = requiresAuth
    }
}

/// Detects the type of a backend instance by probing known API endpoints.
actor InstanceDetector {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Detects the instance type for a given URL.
    /// - Parameter url: The base URL of the instance.
    /// - Returns: The detected instance type, or nil if detection failed.
    func detect(url: URL) async -> InstanceType? {
        let result = await detectWithAuth(url: url)
        return result?.type
    }

    /// Detects the instance type and authentication requirements for a given URL.
    /// - Parameter url: The base URL of the instance.
    /// - Returns: The detection result including type and auth requirements, or nil if detection failed.
    func detectWithAuth(url: URL) async -> InstanceDetectionResult? {
        let result = await detectWithResult(url: url)
        switch result {
        case .success(let detectionResult):
            return detectionResult
        case .failure:
            return nil
        }
    }

    /// Detects the instance type with detailed error reporting.
    /// - Parameter url: The base URL of the instance.
    /// - Returns: Result containing either the detection result or a detailed error.
    func detectWithResult(url: URL) async -> Result<InstanceDetectionResult, DetectionError> {
        // Try each detection method in order of specificity
        // Check Yattee Server first as it's most specific
        do {
            if let result = try await detectYatteeServerWithError(url: url) {
                return .success(result)
            }
        } catch let error as DetectionError {
            return .failure(error)
        } catch {
            // Continue to next detection method
        }

        if await isPeerTube(url: url) {
            return .success(InstanceDetectionResult(type: .peertube))
        }

        if await isInvidious(url: url) {
            return .success(InstanceDetectionResult(type: .invidious))
        }

        if await isPiped(url: url) {
            return .success(InstanceDetectionResult(type: .piped))
        }

        return .failure(.unknownType)
    }

    // MARK: - Detection Methods

    /// Detects if the instance is a Yattee Server.
    /// Auth is always required for Yattee Server (after initial setup).
    /// - Parameter url: The base URL to check.
    /// - Returns: Detection result with type (always requiresAuth=true), or nil if not a Yattee Server.
    private func detectYatteeServer(url: URL) async -> InstanceDetectionResult? {
        try? await detectYatteeServerWithError(url: url)
    }

    /// Detects if the instance is a Yattee Server with detailed error reporting.
    private func detectYatteeServerWithError(url: URL) async throws -> InstanceDetectionResult? {
        let endpoint = GenericEndpoint.get("/info")

        do {
            // First, get raw data to debug the response
            let rawData = try await httpClient.fetchData(endpoint, baseURL: url)
            if let rawString = String(data: rawData, encoding: .utf8) {
                LoggingService.shared.debug("[InstanceDetector] Raw /info response: \(rawString)", category: .api)
            }

            let response = try JSONDecoder().decode(InstanceDetectorModels.YatteeServerInfo.self, from: rawData)
            LoggingService.shared.debug("[InstanceDetector] Parsed YatteeServerInfo: name=\(response.name ?? "nil")", category: .api)

            // Yattee Server returns name containing "yattee"
            if response.name?.lowercased().contains("yattee") == true {
                // Auth is always required for Yattee Server
                let result = InstanceDetectionResult(
                    type: .yatteeServer,
                    requiresAuth: true
                )
                LoggingService.shared.debug("[InstanceDetector] Returning result: type=yatteeServer, requiresAuth=true", category: .api)
                return result
            }
            return nil
        } catch let urlError as URLError {
            LoggingService.shared.error("[InstanceDetector] detectYatteeServer URLError", category: .api, details: urlError.localizedDescription)
            // Check for SSL certificate errors
            if urlError.code == .serverCertificateUntrusted ||
               urlError.code == .serverCertificateHasBadDate ||
               urlError.code == .serverCertificateHasUnknownRoot ||
               urlError.code == .serverCertificateNotYetValid ||
               urlError.code == .clientCertificateRejected {
                throw DetectionError.sslCertificateError
            }
            if urlError.code == .timedOut {
                throw DetectionError.timeout
            }
            throw DetectionError.networkError(urlError.localizedDescription)
        } catch {
            LoggingService.shared.error("[InstanceDetector] detectYatteeServer error", category: .api, details: error.localizedDescription)
            return nil
        }
    }

    /// Checks if the instance is PeerTube by calling /api/v1/config
    private func isPeerTube(url: URL) async -> Bool {
        let endpoint = GenericEndpoint.get("/api/v1/config")

        do {
            let response: InstanceDetectorModels.PeerTubeConfig = try await httpClient.fetch(endpoint, baseURL: url)
            // PeerTube config has specific fields
            return response.instance != nil || response.serverVersion != nil
        } catch {
            return false
        }
    }

    /// Checks if the instance is Invidious by calling /api/v1/stats
    private func isInvidious(url: URL) async -> Bool {
        let endpoint = GenericEndpoint.get("/api/v1/stats")

        do {
            let response: InstanceDetectorModels.InvidiousStats = try await httpClient.fetch(endpoint, baseURL: url)
            // Invidious stats has software.name = "invidious"
            return response.software?.name?.lowercased() == "invidious"
        } catch {
            return false
        }
    }

    /// Checks if the instance is Piped by probing Piped-specific endpoints
    private func isPiped(url: URL) async -> Bool {
        // Piped has a /healthcheck endpoint that returns "OK"
        let healthEndpoint = GenericEndpoint.get("/healthcheck")

        do {
            let data = try await httpClient.fetchData(healthEndpoint, baseURL: url)
            if let text = String(data: data, encoding: .utf8), text.contains("OK") {
                return true
            }
        } catch {
            // Continue to next check
        }

        // Also try /config endpoint which Piped uses
        let configEndpoint = GenericEndpoint.get("/config")

        do {
            let response: InstanceDetectorModels.PipedConfig = try await httpClient.fetch(configEndpoint, baseURL: url)
            // Piped config has specific fields
            return response.donationUrl != nil || response.statusPageUrl != nil
        } catch {
            return false
        }
    }
}

// MARK: - Detection Response Models

/// Namespace for instance detection response models.
/// Using an enum as a namespace to avoid MainActor isolation issues.
enum InstanceDetectorModels {
    struct YatteeServerInfo: Sendable {
        let name: String?
        let version: String?
        let description: String?
    }

    /// Full server info response from /info endpoint for display in UI.
    struct YatteeServerFullInfo: Sendable {
        let name: String?
        let version: String?
        let dependencies: Dependencies?
        let config: Config?
        let sites: [Site]?

        struct Dependencies: Sendable {
            let ytDlp: String?
            let ffmpeg: String?
        }

        struct Config: Sendable {
            let invidiousInstance: String?
            let allowAllSitesForExtraction: Bool?
        }

        struct Site: Sendable {
            let name: String
            let extractorPattern: String?
        }
    }

    struct PeerTubeConfig: Sendable {
        let instance: PeerTubeInstanceInfo?
        let serverVersion: String?

        struct PeerTubeInstanceInfo: Sendable {
            let name: String?
            let shortDescription: String?
        }
    }

    struct InvidiousStats: Sendable {
        let software: InvidiousSoftware?

        struct InvidiousSoftware: Sendable {
            let name: String?
            let version: String?
        }
    }

    struct PipedConfig: Sendable {
        let donationUrl: String?
        let statusPageUrl: String?
        let s3Enabled: Bool?
    }
}

// MARK: - Decodable Conformance (nonisolated)

extension InstanceDetectorModels.YatteeServerInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, version, description
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

extension InstanceDetectorModels.YatteeServerFullInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, version, dependencies, config, sites
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        dependencies = try container.decodeIfPresent(Dependencies.self, forKey: .dependencies)
        config = try container.decodeIfPresent(Config.self, forKey: .config)
        sites = try container.decodeIfPresent([Site].self, forKey: .sites)
    }
}

extension InstanceDetectorModels.YatteeServerFullInfo.Dependencies: Decodable {
    private enum CodingKeys: String, CodingKey {
        case ytDlp = "yt-dlp"
        case ffmpeg
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ytDlp = try container.decodeIfPresent(String.self, forKey: .ytDlp)
        ffmpeg = try container.decodeIfPresent(String.self, forKey: .ffmpeg)
    }
}

// Config and Site use automatic Decodable synthesis since HTTPClient uses .convertFromSnakeCase
extension InstanceDetectorModels.YatteeServerFullInfo.Config: Decodable {}
extension InstanceDetectorModels.YatteeServerFullInfo.Site: Decodable {}

extension InstanceDetectorModels.PeerTubeConfig: Decodable {
    private enum CodingKeys: String, CodingKey {
        case instance, serverVersion
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instance = try container.decodeIfPresent(PeerTubeInstanceInfo.self, forKey: .instance)
        serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
    }
}

extension InstanceDetectorModels.PeerTubeConfig.PeerTubeInstanceInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, shortDescription
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
    }
}

extension InstanceDetectorModels.InvidiousStats: Decodable {
    private enum CodingKeys: String, CodingKey {
        case software
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        software = try container.decodeIfPresent(InvidiousSoftware.self, forKey: .software)
    }
}

extension InstanceDetectorModels.InvidiousStats.InvidiousSoftware: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, version
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
    }
}

extension InstanceDetectorModels.PipedConfig: Decodable {
    private enum CodingKeys: String, CodingKey {
        case donationUrl, statusPageUrl, s3Enabled
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        donationUrl = try container.decodeIfPresent(String.self, forKey: .donationUrl)
        statusPageUrl = try container.decodeIfPresent(String.self, forKey: .statusPageUrl)
        s3Enabled = try container.decodeIfPresent(Bool.self, forKey: .s3Enabled)
    }
}
