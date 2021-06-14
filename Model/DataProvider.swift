import Alamofire
import Foundation

// swiftlint:disable:next final_class
class DataProvider: ObservableObject {
    static let instance = "https://invidious.home.arekf.net"

    static func proxyURLForAsset(_ url: String) -> URL? {
        guard let instanceURLComponents = URLComponents(string: DataProvider.instance),
              var urlComponents = URLComponents(string: url) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host

        return urlComponents.url
    }

    static func request(_ path: String, headers: HTTPHeaders? = nil) -> DataRequest {
        AF.request(apiURLString(path), headers: headers)
    }

    static func apiURLString(_ path: String) -> String {
        "\(instance)/api/v1/\(path)"
    }
}
