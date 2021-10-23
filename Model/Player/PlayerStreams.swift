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

    func loadAvailableStreams(
        _ video: Video,
        completionHandler: @escaping ([Stream]) -> Void = { _ in }
    ) {
        availableStreams = []
        var instancesWithLoadedStreams = [Instance]()

        instances.all.forEach { instance in
            fetchStreams(instance.anonymous.video(video.videoID), instance: instance, video: video) { _ in
                self.completeIfAllInstancesLoaded(
                    instance: instance,
                    streams: self.availableStreams,
                    instancesWithLoadedStreams: &instancesWithLoadedStreams,
                    completionHandler: completionHandler
                )
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
                    self.availableStreams += self.streamsWithInstance(instance: instance, streams: video.streams)
                }
            }
            .onCompletion(onCompletion)
    }

    private func completeIfAllInstancesLoaded(
        instance: Instance,
        streams: [Stream],
        instancesWithLoadedStreams: inout [Instance],
        completionHandler: @escaping ([Stream]) -> Void
    ) {
        instancesWithLoadedStreams.append(instance)
        rebuildTVMenu()

        if instances.all.count == instancesWithLoadedStreams.count {
            completionHandler(streams.sorted { $0.kind < $1.kind })
        }
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
