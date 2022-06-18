import Foundation
import Siesta
import SwiftUI

extension PlayerModel {
    var isLoadingAvailableStreams: Bool {
        streamSelection.isNil || availableStreams.isEmpty
    }

    var isLoadingStream: Bool {
        !stream.isNil && stream != streamSelection
    }

    var availableStreamsSorted: [Stream] {
        availableStreams.sorted(by: streamsSorter)
    }

    func loadAvailableStreams(_ video: Video) {
        availableStreams = []

        guard let playerInstance = InstancesModel.forPlayer ?? InstancesModel.all.first else {
            return
        }

        logger.info("loading streams from \(playerInstance.description)")

        fetchStreams(playerInstance.anonymous.video(video.videoID), instance: playerInstance, video: video)
    }

    private func fetchStreams(
        _ resource: Resource,
        instance: Instance,
        video: Video,
        onCompletion: @escaping (ResponseInfo) -> Void = { _ in }
    ) {
        resource
            .load()
            .onSuccess { response in
                if let video: Video = response.typedContent() {
                    guard video == self.currentVideo else {
                        self.logger.info("ignoring loaded streams from \(instance.description) as current video has changed")
                        return
                    }
                    self.availableStreams += self.streamsWithInstance(instance: instance, streams: video.streams)
                } else {
                    self.logger.critical("no streams available from \(instance.description)")
                }
            }
            .onCompletion(onCompletion)
    }

    func streamsWithInstance(instance: Instance, streams: [Stream]) -> [Stream] {
        streams.map { stream in
            stream.instance = instance

            if instance.app == .invidious {
                if let audio = stream.audioAsset {
                    stream.audioAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: audio)
                }
                if let video = stream.videoAsset {
                    stream.videoAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: video)
                }
            }

            return stream
        }
    }

    func streamsSorter(_ lhs: Stream, _ rhs: Stream) -> Bool {
        if lhs.resolution.isNil || rhs.resolution.isNil {
            return lhs.kind < rhs.kind
        }

        return lhs.kind == rhs.kind ? (lhs.resolution.height > rhs.resolution.height) : (lhs.kind < rhs.kind)
    }
}
