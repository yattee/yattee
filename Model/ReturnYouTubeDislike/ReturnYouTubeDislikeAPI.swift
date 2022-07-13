import Alamofire
import Defaults
import Foundation
import Logging
import SwiftyJSON

final class ReturnYouTubeDislikeAPI: ObservableObject {
    let logger = Logger(label: "stream.yattee.app.rytd")

    @Published var videoID: String?
    @Published var dislikes = -1

    func loadDislikes(videoID: String, completionHandler: @escaping (Int) -> Void = { _ in }) {
        guard self.videoID != videoID else {
            completionHandler(dislikes)
            return
        }

        self.videoID = videoID

        DispatchQueue.main.async { [weak self] in
            self?.requestDislikes(completionHandler: completionHandler)
        }
    }

    private func requestDislikes(completionHandler: @escaping (Int) -> Void = { _ in }) {
        AF.request(votesURL).responseDecodable(of: JSON.self) { [weak self] response in
            guard let self = self else {
                return
            }

            switch response.result {
            case let .success(value):
                let value = JSON(value).dictionaryValue["dislikes"]?.int
                self.dislikes = value ?? -1

            case let .failure(error):
                self.logger.error("failed to load dislikes: \(error.localizedDescription)")
            }

            completionHandler(self.dislikes)
        }
    }

    private var votesURL: String {
        "https://returnyoutubedislikeapi.com/Votes?videoId=\(videoID ?? "")"
    }
}
