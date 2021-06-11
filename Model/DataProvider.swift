import Alamofire
import Foundation

class DataProvider: ObservableObject {
    static let instance = "https://invidious.home.arekf.net"

    static func request(_ path: String, headers: HTTPHeaders? = nil) -> DataRequest {
        AF.request(apiURLString(path), headers: headers)
    }

    static func apiURLString(_ path: String) -> String {
        "\(instance)/api/v1/\(path)"
    }
}
