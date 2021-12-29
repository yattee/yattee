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
        let playerInstance = InstancesModel.forPlayer ?? InstancesModel.all.first

        guard !playerInstance.isNil else {
            return
        }

        logger.info("loading streams from \(playerInstance!.description)")

        fetchStreams(playerInstance!.anonymous.video(video.videoID), instance: playerInstance!, video: video) { _ in
            InstancesModel.all.filter { $0 != playerInstance }.forEach { instance in
                self.logger.info("loading streams from \(instance.description)")
                self.fetchStreams(instance.anonymous.video(video.videoID), instance: instance, video: video)
            }
        }
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
                stream.audioAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: stream.audioAsset)
                stream.videoAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: stream.videoAsset)
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
