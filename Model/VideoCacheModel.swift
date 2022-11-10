import Foundation
import Logging
import SwiftyJSON

struct VideoCacheModel {
    static let shared = VideoCacheModel()
    var logger = Logger(label: "stream.yattee.video-cache")

    func saveVideo(id: Video.ID, app: VideosApp, json: JSON) {
        guard !json.isEmpty else { return }
        var jsonWithApp = json
        jsonWithApp["app"].string = app.rawValue
        try! CacheModel.shared.videoStorage!.setObject(jsonWithApp, forKey: id)
        logger.info("saving video \(id)")
    }

    func loadVideo(id: Video.ID) -> JSON? {
        logger.info("loading video \(id)")

        let json = try? CacheModel.shared.videoStorage?.object(forKey: id)
        return json
    }
}
