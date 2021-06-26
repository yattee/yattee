import Alamofire
import Foundation
import SwiftyJSON

final class PlaylistsProvider: DataProvider {
    @Published var playlists = [Playlist]()

    let profile = Profile()

    func load(successHandler: @escaping ([Playlist]) -> Void = { _ in }) {
        let headers = HTTPHeaders([HTTPHeader(name: "Cookie", value: "SID=\(profile.sid)")])
        DataProvider.request("auth/playlists", headers: headers).responseJSON { response in
            switch response.result {
            case let .success(value):
                self.playlists = JSON(value).arrayValue.map { Playlist($0) }
                successHandler(self.playlists)
            case let .failure(error):
                print(error)
            }
        }
    }
}
