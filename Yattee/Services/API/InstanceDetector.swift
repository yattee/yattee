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
    /// The instance is fronted by an HTTP Basic Auth challenge (401). The user must
    /// supply credentials before detection can identify the backend type.
    case basicAuthRequired
    /// Detection was retried with HTTP Basic Auth credentials but the server still
    /// returned 401 — the credentials are invalid.
    case basicAuthInvalid

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
        case .basicAuthRequired:
            return String(localized: "sources.error.basicAuthRequired")
        case .basicAuthInvalid:
            return String(localized: "sources.error.basicAuthInvalid")
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
    /// - Parameters:
    ///   - url: The base URL of the instance.
    ///   - basicAuthHeader: Optional HTTP Basic Auth header value (e.g., "Basic dXNlcjpwYXNz")
    ///     to inject into every probe. Used to retry detection after the user provides
    ///     credentials for an instance fronted by a reverse proxy.
    /// - Returns: Result containing either the detection result or a detailed error.
    func detectWithResult(
        url: URL,
        basicAuthHeader: String? = nil
    ) async -> Result<InstanceDetectionResult, DetectionError> {
        let extraHeaders: [String: String]? = basicAuthHeader.map { ["Authorization": $0] }

        // A 401 from a single probe is *not* enough to conclude that credentials are
        // invalid. Some probe paths (e.g. Yattee Server's `/info`) trigger an HTTP
        // redirect on Invidious, and iOS URLSession strips the Authorization header
        // when following redirects, so the redirected request 401s even when the
        // credentials are valid. We instead consider credentials bad only if EVERY
        // probe failed with 401 and none matched.
        var sawUnauthorized = false

        // Try each detection method in order of specificity.
        // Check Yattee Server first as it's most specific.
        do {
            if let result = try await detectYatteeServerWithError(url: url, extraHeaders: extraHeaders) {
                return .success(result)
            }
        } catch let error as DetectionError {
            return .failure(error)
        } catch APIError.unauthorized {
            sawUnauthorized = true
        } catch {
            // Continue to next detection method
        }

        do {
            if try await isPeerTube(url: url, extraHeaders: extraHeaders) {
                return .success(InstanceDetectionResult(type: .peertube))
            }
        } catch APIError.unauthorized {
            sawUnauthorized = true
        } catch {
            // Continue to next detection method
        }

        do {
            if try await isInvidious(url: url, extraHeaders: extraHeaders) {
                return .success(InstanceDetectionResult(type: .invidious))
            }
        } catch APIError.unauthorized {
            sawUnauthorized = true
        } catch {
            // Continue to next detection method
        }

        do {
            if try await isPiped(url: url, extraHeaders: extraHeaders) {
                return .success(InstanceDetectionResult(type: .piped))
            }
        } catch APIError.unauthorized {
            sawUnauthorized = true
        } catch {
            // Fall through
        }

        // No probe matched. If at least one probe returned 401, the instance is
        // (or appears to be) behind HTTP Basic Auth. Distinguish "needs creds" from
        // "creds rejected" by whether the caller already supplied a header.
        if sawUnauthorized {
            return .failure(basicAuthHeader == nil ? .basicAuthRequired : .basicAuthInvalid)
        }
        return .failure(.unknownType)
    }

    // MARK: - Detection Methods

    /// Detects if the instance is a Yattee Server with detailed error reporting.
    /// Throws `APIError.unauthorized` if the probe receives a 401, so the caller can prompt for credentials.
    private func detectYatteeServerWithError(
        url: URL,
        extraHeaders: [String: String]? = nil
    ) async throws -> InstanceDetectionResult? {
        let endpoint = GenericEndpoint.get("/info")

        do {
            // First, get raw data to debug the response
            let rawData = try await httpClient.fetchData(endpoint, baseURL: url, customHeaders: extraHeaders)
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
        } catch APIError.unauthorized {
            LoggingService.shared.debug("[InstanceDetector] /info returned 401 — basic auth required", category: .api)
            throw APIError.unauthorized
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

    /// Checks if the instance is PeerTube by calling /api/v1/config.
    /// Re-throws `APIError.unauthorized` so the caller can prompt for basic-auth credentials.
    private func isPeerTube(url: URL, extraHeaders: [String: String]? = nil) async throws -> Bool {
        let endpoint = GenericEndpoint.get("/api/v1/config")

        do {
            let response: InstanceDetectorModels.PeerTubeConfig = try await httpClient.fetch(endpoint, baseURL: url, customHeaders: extraHeaders)
            // PeerTube config has specific fields
            return response.instance != nil || response.serverVersion != nil
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch {
            return false
        }
    }

    /// Checks if the instance is Invidious by calling /api/v1/stats.
    /// Re-throws `APIError.unauthorized` so the caller can prompt for basic-auth credentials.
    private func isInvidious(url: URL, extraHeaders: [String: String]? = nil) async throws -> Bool {
        let endpoint = GenericEndpoint.get("/api/v1/stats")

        do {
            let response: InstanceDetectorModels.InvidiousStats = try await httpClient.fetch(endpoint, baseURL: url, customHeaders: extraHeaders)
            // Invidious stats has software.name = "invidious"
            return response.software?.name?.lowercased() == "invidious"
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch {
            return false
        }
    }

    /// Checks if the instance is Piped by probing Piped-specific endpoints.
    /// Re-throws `APIError.unauthorized` so the caller can prompt for basic-auth credentials.
    private func isPiped(url: URL, extraHeaders: [String: String]? = nil) async throws -> Bool {
        // Piped has a /healthcheck endpoint that returns "OK"
        let healthEndpoint = GenericEndpoint.get("/healthcheck")

        do {
            let data = try await httpClient.fetchData(healthEndpoint, baseURL: url, customHeaders: extraHeaders)
            if let text = String(data: data, encoding: .utf8), text.contains("OK") {
                return true
            }
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch {
            // Continue to next check
        }

        // Also try /config endpoint which Piped uses
        let configEndpoint = GenericEndpoint.get("/config")

        do {
            let response: InstanceDetectorModels.PipedConfig = try await httpClient.fetch(configEndpoint, baseURL: url, customHeaders: extraHeaders)
            // Piped config has specific fields
            return response.donationUrl != nil || response.statusPageUrl != nil
        } catch APIError.unauthorized {
            throw APIError.unauthorized
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
