import Foundation
import Siesta

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
            switch instance.app {
            case .piped:
                fetchPipedStreams(instance, video: video) { _ in
                    self.completeIfAllInstancesLoaded(
                        instance: instance,
                        streams: self.availableStreams,
                        instancesWithLoadedStreams: &instancesWithLoadedStreams,
                        completionHandler: completionHandler
                    )
                }

            case .invidious:
                fetchInvidiousStreams(instance, video: video) { _ in
                    self.completeIfAllInstancesLoaded(
                        instance: instance,
                        streams: self.availableStreams,
                        instancesWithLoadedStreams: &instancesWithLoadedStreams,
                        completionHandler: completionHandler
                    )
                }
            }
        }
    }

    private func fetchInvidiousStreams(
        _ instance: Instance,
        video: Video,
        onCompletion: @escaping (ResponseInfo) -> Void = { _ in }
    ) {
        invidious(instance)
            .video(video.videoID)
            .load()
            .onSuccess { response in
                if let video: Video = response.typedContent() {
                    self.availableStreams += self.streamsWithAssetsFromInstance(instance: instance, streams: video.streams)
                }
            }
            .onCompletion(onCompletion)
    }

    private func fetchPipedStreams(
        _ instance: Instance,
        video: Video,
        onCompletion: @escaping (ResponseInfo) -> Void = { _ in }
    ) {
        piped(instance)
            .streams(id: video.videoID)
            .load()
            .onSuccess { response in
                if let pipedStreams: [Stream] = response.typedContent() {
                    self.availableStreams += self.streamsWithInstance(instance: instance, streams: pipedStreams)
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

        if instances.all.count == instancesWithLoadedStreams.count {
            completionHandler(streams.sorted { $0.kind < $1.kind })
        }
    }

    func streamsWithInstance(instance: Instance, streams: [Stream]) -> [Stream] {
        streams.map { stream in
            stream.instance = instance
            return stream
        }
    }

    func streamsWithAssetsFromInstance(instance: Instance, streams: [Stream]) -> [Stream] {
        streams.map { stream in stream.withAssetsFrom(instance) }
    }

    func streamsSorter(_ lhs: Stream, _ rhs: Stream) -> Bool {
        lhs.kind == rhs.kind ? (lhs.resolution.height > rhs.resolution.height) : (lhs.kind < rhs.kind)
    }
}
