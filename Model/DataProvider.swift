import Alamofire
import Foundation

class DataProvider: ObservableObject {
    static let instance = "https://invidious.home.arekf.net"

    static func request(_ path: String) -> DataRequest {
        return AF.request(apiURLString(path))
    }

    static func apiURLString(_ path: String) -> String {
        "\(instance)/api/v1/\(path)"
    }
}
