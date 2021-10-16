import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class PipedAPI: Service, ObservableObject {
    @Published var account: Instance.Account!

    var anonymousAccount: Instance.Account {
        .init(instanceID: account.instance.id, name: "Anonymous", url: account.instance.url)
    }

    init(account: Instance.Account? = nil) {
        super.init()

        guard account != nil else {
            return
        }

        setAccount(account!)
    }

    func setAccount(_ account: Instance.Account) {
        self.account = account

        configure()
    }

    func configure() {
        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configureTransformer(pathPattern("streams/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Stream] in
            self.extractStreams(content)
        }
    }

    private func extractStreams(_ content: Entity<JSON>) -> [Stream] {
        var streams = [Stream]()

        if let hlsURL = content.json.dictionaryValue["hls"]?.url {
            streams.append(Stream(hlsURL: hlsURL))
        }

        guard let audioStream = compatibleAudioStreams(content).first else {
            return streams
        }

        let videoStreams = compatibleVideoStream(content)

        videoStreams.forEach { videoStream in
            let audioAsset = AVURLAsset(url: audioStream.dictionaryValue["url"]!.url!)
            let videoAsset = AVURLAsset(url: videoStream.dictionaryValue["url"]!.url!)

            let videoOnly = videoStream.dictionaryValue["videoOnly"]?.boolValue ?? true
            let resolution = Stream.Resolution.from(resolution: videoStream.dictionaryValue["quality"]!.stringValue)

            if videoOnly {
                streams.append(
                    Stream(audioAsset: audioAsset, videoAsset: videoAsset, resolution: resolution, kind: .adaptive)
                )
            } else {
                streams.append(
                    SingleAssetStream(avAsset: videoAsset, resolution: resolution, kind: .stream)
                )
            }
        }

        return streams
    }

    private func compatibleAudioStreams(_ content: Entity<JSON>) -> [JSON] {
        content
            .json
            .dictionaryValue["audioStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"]?.stringValue == "M4A" }
            .sorted {
                $0.dictionaryValue["bitrate"]?.intValue ?? 0 > $1.dictionaryValue["bitrate"]?.intValue ?? 0
            } ?? []
    }

    private func compatibleVideoStream(_ content: Entity<JSON>) -> [JSON] {
        content
            .json
            .dictionaryValue["videoStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"] == "MPEG_4" } ?? []
    }

    private func pathPattern(_ path: String) -> String {
        "**\(path)"
    }

    func streams(id: Video.ID) -> Resource {
        resource(baseURL: account.instance.url, path: "streams/\(id)")
    }
}
