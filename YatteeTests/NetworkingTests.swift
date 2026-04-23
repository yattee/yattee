//
//  NetworkingTests.swift
//  YatteeTests
//
//  Tests for networking layer components.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Endpoint Tests

@Suite("Endpoint Tests")
@MainActor
struct EndpointTests {

    @Test("GET endpoint construction")
    func getEndpoint() {
        let endpoint = GenericEndpoint.get("/api/v1/videos")
        #expect(endpoint.path == "/api/v1/videos")
        #expect(endpoint.method == .get)
        #expect(endpoint.queryItems == nil)
        #expect(endpoint.body == nil)
    }

    @Test("GET endpoint with query parameters")
    func getEndpointWithQuery() {
        let endpoint = GenericEndpoint.get("/api/v1/search", query: [
            "q": "test",
            "page": "1"
        ])
        #expect(endpoint.path == "/api/v1/search")
        #expect(endpoint.queryItems?.count == 2)

        let queryDict = Dictionary(uniqueKeysWithValues: endpoint.queryItems!.map { ($0.name, $0.value) })
        #expect(queryDict["q"] == "test")
        #expect(queryDict["page"] == "1")
    }

    @Test("POST endpoint with body")
    func postEndpointWithBody() throws {
        struct TestBody: Encodable {
            let name: String
        }
        let body = TestBody(name: "test")
        let endpoint = GenericEndpoint.post("/api/v1/create", body: body)
        #expect(endpoint.path == "/api/v1/create")
        #expect(endpoint.method == .post)
        #expect(endpoint.body != nil)
    }

    @Test("Generic endpoint with custom timeout")
    func endpointWithTimeout() {
        let endpoint = GenericEndpoint(path: "/slow", timeout: 60)
        #expect(endpoint.timeout == 60)
    }

    @Test("Default endpoint timeout is 30 seconds")
    func defaultTimeout() {
        let endpoint = GenericEndpoint.get("/fast")
        #expect(endpoint.timeout == 30)
    }
}

// MARK: - APIError Tests

@Suite("APIError Tests")
@MainActor
struct APIErrorTests {

    @Test("APIError descriptions")
    func errorDescriptions() {
        let invalidURL = APIError.invalidURL
        #expect(invalidURL.localizedDescription.contains("URL"))

        let httpError = APIError.httpError(statusCode: 404, message: nil)
        #expect(httpError.localizedDescription.contains("404"))

        let timeout = APIError.timeout
        #expect(timeout.localizedDescription.contains("timed out"))

        let notFound = APIError.notFound(nil)
        #expect(notFound.localizedDescription.contains("not found"))
    }

    @Test("All simple error descriptions")
    func allSimpleErrorDescriptions() {
        #expect(APIError.invalidURL.errorDescription == "Invalid URL")
        #expect(APIError.timeout.errorDescription == "Request timed out")
        #expect(APIError.noConnection.errorDescription == "No network connection")
        #expect(APIError.cancelled.errorDescription == "Request was cancelled")
        #expect(APIError.unauthorized.errorDescription == "Authentication required")
        #expect(APIError.notFound(nil).errorDescription == "Resource not found")
        #expect(APIError.commentsDisabled.errorDescription == "Comments are disabled")
        #expect(APIError.noInstance.errorDescription == "No suitable instance available")
        #expect(APIError.noStreams.errorDescription == "No playable streams available")
        #expect(APIError.invalidRequest.errorDescription == "Invalid request")
    }

    @Test("Decoding error description")
    func decodingErrorDescription() {
        let error = APIError.decodingError("Missing key 'title'")
        #expect(error.errorDescription?.contains("Missing key 'title'") == true)
    }

    @Test("Server error description")
    func serverErrorDescription() {
        let error = APIError.serverError("Internal server error")
        #expect(error.errorDescription?.contains("Internal server error") == true)
    }

    @Test("Rate limited description with retry after")
    func rateLimitedWithRetry() {
        let error = APIError.rateLimited(retryAfter: 60)
        #expect(error.errorDescription?.contains("60") == true)
    }

    @Test("Rate limited description without retry after")
    func rateLimitedWithoutRetry() {
        let error = APIError.rateLimited(retryAfter: nil)
        #expect(error.errorDescription == "Rate limited")
    }

    @Test("Unknown error description")
    func unknownErrorDescription() {
        let error = APIError.unknown("Something went wrong")
        #expect(error.errorDescription == "Something went wrong")
    }

    @Test("APIError equality")
    func errorEquality() {
        #expect(APIError.invalidURL == APIError.invalidURL)
        #expect(APIError.httpError(statusCode: 404, message: nil) == APIError.httpError(statusCode: 404, message: nil))
        #expect(APIError.httpError(statusCode: 404, message: nil) != APIError.httpError(statusCode: 500, message: nil))
        #expect(APIError.timeout == APIError.timeout)
        #expect(APIError.notFound(nil) == APIError.notFound(nil))
        #expect(APIError.unauthorized == APIError.unauthorized)
    }

    @Test("APIError equality for parameterized errors")
    func parameterizedErrorEquality() {
        #expect(APIError.decodingError("msg") == APIError.decodingError("msg"))
        #expect(APIError.decodingError("msg1") != APIError.decodingError("msg2"))

        #expect(APIError.serverError("msg") == APIError.serverError("msg"))
        #expect(APIError.serverError("msg1") != APIError.serverError("msg2"))

        #expect(APIError.rateLimited(retryAfter: 30) == APIError.rateLimited(retryAfter: 30))
        #expect(APIError.rateLimited(retryAfter: nil) == APIError.rateLimited(retryAfter: nil))
        #expect(APIError.rateLimited(retryAfter: 30) != APIError.rateLimited(retryAfter: 60))

        #expect(APIError.unknown("msg") == APIError.unknown("msg"))
        #expect(APIError.unknown("msg1") != APIError.unknown("msg2"))

        #expect(APIError.notFound(nil) == APIError.notFound(nil))
        #expect(APIError.notFound("detail") == APIError.notFound("detail"))
        #expect(APIError.notFound("detail1") != APIError.notFound("detail2"))
        #expect(APIError.notFound(nil) != APIError.notFound("detail"))
    }

    @Test("notFound error with detail message")
    func notFoundWithDetail() {
        let noDetail = APIError.notFound(nil)
        #expect(noDetail.errorDescription == "Resource not found")

        let withDetail = APIError.notFound("Video not found: This live event will begin in 11 days.")
        #expect(withDetail.errorDescription == "Video not found: This live event will begin in 11 days.")
    }

    @Test("Different error types are not equal")
    func differentTypesNotEqual() {
        #expect(APIError.invalidURL != APIError.timeout)
        #expect(APIError.notFound(nil) != APIError.unauthorized)
        #expect(APIError.commentsDisabled != APIError.noStreams)
    }

    @Test("APIError isRetryable")
    func retryableErrors() {
        #expect(APIError.timeout.isRetryable == true)
        #expect(APIError.noConnection.isRetryable == true)
        #expect(APIError.rateLimited(retryAfter: 60).isRetryable == true)
        #expect(APIError.httpError(statusCode: 500, message: nil).isRetryable == true)
        #expect(APIError.httpError(statusCode: 429, message: nil).isRetryable == true)

        #expect(APIError.invalidURL.isRetryable == false)
        #expect(APIError.notFound(nil).isRetryable == false)
        #expect(APIError.unauthorized.isRetryable == false)
        #expect(APIError.httpError(statusCode: 400, message: nil).isRetryable == false)
    }

    @Test("All non-retryable errors")
    func allNonRetryableErrors() {
        #expect(APIError.invalidURL.isRetryable == false)
        #expect(APIError.decodingError("").isRetryable == false)
        #expect(APIError.cancelled.isRetryable == false)
        #expect(APIError.serverError("").isRetryable == false)
        #expect(APIError.unauthorized.isRetryable == false)
        #expect(APIError.notFound(nil).isRetryable == false)
        #expect(APIError.commentsDisabled.isRetryable == false)
        #expect(APIError.noInstance.isRetryable == false)
        #expect(APIError.noStreams.isRetryable == false)
        #expect(APIError.invalidRequest.isRetryable == false)
        #expect(APIError.unknown("").isRetryable == false)
    }

    @Test("Server errors (5xx) are retryable")
    func serverErrorsRetryable() {
        #expect(APIError.httpError(statusCode: 500, message: nil).isRetryable == true)
        #expect(APIError.httpError(statusCode: 502, message: nil).isRetryable == true)
        #expect(APIError.httpError(statusCode: 503, message: nil).isRetryable == true)
        #expect(APIError.httpError(statusCode: 504, message: nil).isRetryable == true)
    }

    @Test("Decoding error from Swift DecodingError types")
    func decodingErrorFactory() {
        // Test typeMismatch
        let typeMismatchContext = DecodingError.Context(codingPath: [], debugDescription: "Expected String")
        let typeMismatch = DecodingError.typeMismatch(String.self, typeMismatchContext)
        let apiError1 = APIError.decodingError(typeMismatch)
        #expect(apiError1.errorDescription?.contains("Type mismatch") == true)

        // Test valueNotFound
        let valueNotFoundContext = DecodingError.Context(codingPath: [], debugDescription: "No value")
        let valueNotFound = DecodingError.valueNotFound(Int.self, valueNotFoundContext)
        let apiError2 = APIError.decodingError(valueNotFound)
        #expect(apiError2.errorDescription?.contains("Value not found") == true)

        // Test dataCorrupted
        let dataCorruptedContext = DecodingError.Context(codingPath: [], debugDescription: "Corrupted")
        let dataCorrupted = DecodingError.dataCorrupted(dataCorruptedContext)
        let apiError3 = APIError.decodingError(dataCorrupted)
        #expect(apiError3.errorDescription?.contains("Data corrupted") == true)
    }
}

// MARK: - URL Building Tests

@Suite("URL Building Tests")
@MainActor
struct URLBuildingTests {

    @Test("Build URL from base and endpoint")
    func buildURL() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = GenericEndpoint.get("/v1/videos")

        let request = try endpoint.urlRequest(baseURL: baseURL)
        #expect(request.url?.absoluteString == "https://api.example.com/v1/videos")
    }

    @Test("Build URL with query parameters")
    func buildURLWithQuery() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = GenericEndpoint.get("/search", query: [
            "q": "hello world",
            "limit": "10"
        ])

        let request = try endpoint.urlRequest(baseURL: baseURL)
        let urlString = request.url?.absoluteString ?? ""

        #expect(urlString.contains("q=hello%20world"))
        #expect(urlString.contains("limit=10"))
    }

    @Test("URLRequest has correct method")
    func requestMethod() throws {
        let baseURL = URL(string: "https://api.example.com")!

        let getEndpoint = GenericEndpoint.get("/resource")
        let getRequest = try getEndpoint.urlRequest(baseURL: baseURL)
        #expect(getRequest.httpMethod == "GET")

        let postEndpoint = GenericEndpoint.post("/resource", body: ["key": "value"])
        let postRequest = try postEndpoint.urlRequest(baseURL: baseURL)
        #expect(postRequest.httpMethod == "POST")
    }

    @Test("URLRequest has JSON Accept header")
    func acceptHeader() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = GenericEndpoint.get("/resource")
        let request = try endpoint.urlRequest(baseURL: baseURL)

        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }
}

// MARK: - HTTPMethod Tests

@Suite("HTTPMethod Tests")
@MainActor
struct HTTPMethodTests {

    @Test("HTTPMethod raw values")
    func rawValues() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }
}
