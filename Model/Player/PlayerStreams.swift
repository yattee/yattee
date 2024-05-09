import AVFoundation
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

    func loadAvailableStreams(_ video: Video, onCompletion: @escaping (ResponseInfo) -> Void = { _ in }) {
        captions = nil
        availableStreams = []

        guard let playerInstance else { return }

        guard let api = playerAPI(video) else { return }
        logger.info("loading streams from \(playerInstance.description)")
        fetchStreams(api.video(video.videoID), instance: playerInstance, video: video, onCompletion: onCompletion)
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
                    VideosCacheModel.shared.storeVideo(video)
                    guard video.videoID == self.currentVideo?.videoID else {
                        self.logger.info("ignoring loaded streams from \(instance.description) as current video has changed")
                        return
                    }
                    self.streamsWithInstance(instance: instance, streams: video.streams) { processedStreams in
                        self.availableStreams = processedStreams
                    }
                } else {
                    self.logger.critical("no streams available from \(instance.description)")
                }
            }
            .onCompletion(onCompletion)
            .onFailure { [weak self] responseError in
                self?.navigation.presentAlert(title: "Could not load streams", message: responseError.userMessage)
                self?.videoBeingOpened = nil
            }
    }

    func streamsWithInstance(instance _: Instance, streams: [Stream], completion: @escaping ([Stream]) -> Void) {
        let forbiddenAssetTestGroup = DispatchGroup()
        var hasForbiddenAsset = false

        let (nonHLSAssets, hlsURLs) = getAssets(from: streams)

        if let randomStream = nonHLSAssets.randomElement() {
            let instance = randomStream.0
            let asset = randomStream.1
            let url = randomStream.2
            let requestRange = randomStream.3

            if let asset = asset, let instance = instance, !instance.proxiesVideos {
                if instance.app == .invidious {
                    testAsset(url: url, range: requestRange, isHLS: false, forbiddenAssetTestGroup: forbiddenAssetTestGroup) { isForbidden in
                        hasForbiddenAsset = isForbidden
                    }
                } else if instance.app == .piped {
                    testPipedAssets(asset: asset, requestRange: requestRange!, isHLS: false, forbiddenAssetTestGroup: forbiddenAssetTestGroup, completion: { isForbidden in
                        hasForbiddenAsset = isForbidden
                    })
                }
            }
        } else if let randomHLS = hlsURLs.randomElement() {
            let instance = randomHLS.0
            let asset = AVURLAsset(url: randomHLS.1)

            if instance?.app == .piped {
                testPipedAssets(asset: asset, requestRange: nil, isHLS: false, forbiddenAssetTestGroup: forbiddenAssetTestGroup, completion: { isForbidden in
                    hasForbiddenAsset = isForbidden
                })
            }
        }

        forbiddenAssetTestGroup.notify(queue: .main) {
            let processedStreams = streams.map { stream -> Stream in
                if let instance = stream.instance {
                    if instance.app == .invidious {
                        if hasForbiddenAsset || instance.proxiesVideos {
                            if let audio = stream.audioAsset {
                                stream.audioAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: audio)
                            }
                            if let video = stream.videoAsset {
                                stream.videoAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: video)
                            }
                        }
                    } else if instance.app == .piped, !instance.proxiesVideos, !hasForbiddenAsset {
                        if let hlsURL = stream.hlsURL {
                            forbiddenAssetTestGroup.enter()
                            PipedAPI.nonProxiedAsset(url: hlsURL) { nonProxiedURL in
                                if let nonProxiedURL = nonProxiedURL {
                                    stream.hlsURL = nonProxiedURL.url
                                }
                                forbiddenAssetTestGroup.leave()
                            }
                        } else {
                            if let audio = stream.audioAsset {
                                forbiddenAssetTestGroup.enter()
                                PipedAPI.nonProxiedAsset(asset: audio) { nonProxiedAudioAsset in
                                    stream.audioAsset = nonProxiedAudioAsset
                                    forbiddenAssetTestGroup.leave()
                                }
                            }
                            if let video = stream.videoAsset {
                                forbiddenAssetTestGroup.enter()
                                PipedAPI.nonProxiedAsset(asset: video) { nonProxiedVideoAsset in
                                    stream.videoAsset = nonProxiedVideoAsset
                                    forbiddenAssetTestGroup.leave()
                                }
                            }
                        }
                    }
                }
                return stream
            }

            forbiddenAssetTestGroup.notify(queue: .main) {
                completion(processedStreams)
            }
        }
    }

    private func getAssets(from streams: [Stream]) -> (nonHLSAssets: [(Instance?, AVURLAsset?, URL, String?)], hlsURLs: [(Instance?, URL)]) {
        var nonHLSAssets = [(Instance?, AVURLAsset?, URL, String?)]()
        var hlsURLs = [(Instance?, URL)]()

        for stream in streams {
            if stream.isHLS {
                if let url = stream.hlsURL?.url {
                    hlsURLs.append((stream.instance, url))
                }
            } else {
                if let asset = stream.audioAsset {
                    nonHLSAssets.append((stream.instance, asset, asset.url, stream.requestRange))
                }
                if let asset = stream.videoAsset {
                    nonHLSAssets.append((stream.instance, asset, asset.url, stream.requestRange))
                }
            }
        }

        return (nonHLSAssets, hlsURLs)
    }

    private func testAsset(url: URL, range: String?, isHLS: Bool, forbiddenAssetTestGroup: DispatchGroup, completion: @escaping (Bool) -> Void) {
        let randomEnd = Int.random(in: 200 ... 800)
        let requestRange = range ?? "0-\(randomEnd)"
        let HTTPStatusForbidden = 403

        forbiddenAssetTestGroup.enter()
        URLTester.testURLResponse(url: url, range: requestRange, isHLS: isHLS) { statusCode in
            completion(statusCode == HTTPStatusForbidden)
            forbiddenAssetTestGroup.leave()
        }
    }

    private func testPipedAssets(asset: AVURLAsset, requestRange: String?, isHLS: Bool, forbiddenAssetTestGroup: DispatchGroup, completion: @escaping (Bool) -> Void) {
        PipedAPI.nonProxiedAsset(asset: asset) { nonProxiedAsset in
            if let nonProxiedAsset = nonProxiedAsset {
                self.testAsset(url: nonProxiedAsset.url, range: requestRange, isHLS: isHLS, forbiddenAssetTestGroup: forbiddenAssetTestGroup, completion: completion)
            }
        }
    }

    func streamsSorter(_ lhs: Stream, _ rhs: Stream) -> Bool {
        if lhs.resolution.isNil || rhs.resolution.isNil {
            return lhs.kind < rhs.kind
        }

        return lhs.kind == rhs.kind ? (lhs.resolution.height > rhs.resolution.height) : (lhs.kind < rhs.kind)
    }
}
