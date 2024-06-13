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

    func streamsWithInstance(instance: Instance, streams: [Stream], completion: @escaping ([Stream]) -> Void) {
        // Queue for stream processing
        let streamProcessingQueue = DispatchQueue(label: "stream.yattee.streamProcessing.Queue")
        // Queue for accessing the processedStreams array
        let processedStreamsQueue = DispatchQueue(label: "stream.yattee.processedStreams.Queue")
        // DispatchGroup for managing multiple tasks
        let streamProcessingGroup = DispatchGroup()

        var processedStreams = [Stream]()
        let instance = instance

        var hasForbiddenAsset = false
        var hasAllowedAsset = false

        for stream in streams {
            streamProcessingQueue.async(group: streamProcessingGroup) {
                let forbiddenAssetTestGroup = DispatchGroup()
                if !hasAllowedAsset, !hasForbiddenAsset, !instance.proxiesVideos, stream.format != Stream.Format.unknown {
                    let (nonHLSAssets, hlsURLs) = self.getAssets(from: [stream])
                    if let firstStream = nonHLSAssets.first {
                        let asset = firstStream.0
                        let url = firstStream.1
                        let requestRange = firstStream.2

                        if instance.app == .invidious {
                            self.testAsset(url: url, range: requestRange, isHLS: false, forbiddenAssetTestGroup: forbiddenAssetTestGroup) { status in
                                switch status {
                                case HTTPStatus.Forbidden:
                                    hasForbiddenAsset = true
                                case HTTPStatus.PartialContent:
                                    hasAllowedAsset = true
                                case HTTPStatus.OK:
                                    hasAllowedAsset = true
                                default:
                                    break
                                }
                            }
                        } else if instance.app == .piped {
                            self.testPipedAssets(asset: asset!, requestRange: requestRange, isHLS: false, forbiddenAssetTestGroup: forbiddenAssetTestGroup) { status in
                                switch status {
                                case HTTPStatus.Forbidden:
                                    hasForbiddenAsset = true
                                case HTTPStatus.PartialContent:
                                    hasAllowedAsset = true
                                case HTTPStatus.OK:
                                    hasAllowedAsset = true
                                default:
                                    break
                                }
                            }
                        }
                    } else if let firstHLS = hlsURLs.first {
                        let asset = AVURLAsset(url: firstHLS)
                        if instance.app == .piped {
                            self.testPipedAssets(asset: asset, requestRange: nil, isHLS: true, forbiddenAssetTestGroup: forbiddenAssetTestGroup) { status in
                                switch status {
                                case HTTPStatus.Forbidden:
                                    hasForbiddenAsset = true
                                case HTTPStatus.PartialContent:
                                    hasAllowedAsset = true
                                case HTTPStatus.OK:
                                    hasAllowedAsset = true
                                default:
                                    break
                                }
                            }
                        }
                    }
                }
                forbiddenAssetTestGroup.wait()

                // Post-processing code
                if instance.app == .invidious, hasForbiddenAsset || instance.proxiesVideos {
                    if let audio = stream.audioAsset {
                        stream.audioAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: audio)
                    }
                    if let video = stream.videoAsset {
                        stream.videoAsset = InvidiousAPI.proxiedAsset(instance: instance, asset: video)
                    }
                } else if instance.app == .piped, !instance.proxiesVideos, !hasForbiddenAsset {
                    if let hlsURL = stream.hlsURL {
                        PipedAPI.nonProxiedAsset(url: hlsURL) { possibleNonProxiedURL in
                            if let nonProxiedURL = possibleNonProxiedURL {
                                stream.hlsURL = nonProxiedURL.url
                            }
                        }
                    } else {
                        if let audio = stream.audioAsset {
                            PipedAPI.nonProxiedAsset(asset: audio) { nonProxiedAudioAsset in
                                stream.audioAsset = nonProxiedAudioAsset
                            }
                        }
                        if let video = stream.videoAsset {
                            PipedAPI.nonProxiedAsset(asset: video) { nonProxiedVideoAsset in
                                stream.videoAsset = nonProxiedVideoAsset
                            }
                        }
                    }
                }

                // Append to processedStreams within the processedStreamsQueue
                processedStreamsQueue.sync {
                    processedStreams.append(stream)
                }
            }
        }

        streamProcessingGroup.notify(queue: .main) {
            // Access and pass processedStreams within the processedStreamsQueue block
            processedStreamsQueue.sync {
                completion(processedStreams)
            }
        }
    }

    private func getAssets(from streams: [Stream]) -> (nonHLSAssets: [(AVURLAsset?, URL, String?)], hlsURLs: [URL]) {
        var nonHLSAssets = [(AVURLAsset?, URL, String?)]()
        var hlsURLs = [URL]()

        for stream in streams {
            if stream.isHLS {
                if let url = stream.hlsURL?.url {
                    hlsURLs.append(url)
                }
            } else {
                if let asset = stream.audioAsset {
                    nonHLSAssets.append((asset, asset.url, stream.requestRange))
                }
                if let asset = stream.videoAsset {
                    nonHLSAssets.append((asset, asset.url, stream.requestRange))
                }
            }
        }

        return (nonHLSAssets, hlsURLs)
    }

    private func testAsset(url: URL, range: String?, isHLS: Bool, forbiddenAssetTestGroup: DispatchGroup, completion: @escaping (Int) -> Void) {
        // In case the range is nil, generate a random one.
        let randomEnd = Int.random(in: 200 ... 800)
        let requestRange = range ?? "0-\(randomEnd)"

        forbiddenAssetTestGroup.enter()
        URLTester.testURLResponse(url: url, range: requestRange, isHLS: isHLS) { statusCode in
            completion(statusCode)
            forbiddenAssetTestGroup.leave()
        }
    }

    private func testPipedAssets(asset: AVURLAsset, requestRange: String?, isHLS: Bool, forbiddenAssetTestGroup: DispatchGroup, completion: @escaping (Int) -> Void) {
        PipedAPI.nonProxiedAsset(asset: asset) { possibleNonProxiedAsset in
            if let nonProxiedAsset = possibleNonProxiedAsset {
                self.testAsset(url: nonProxiedAsset.url, range: requestRange, isHLS: isHLS, forbiddenAssetTestGroup: forbiddenAssetTestGroup, completion: completion)
            } else {
                completion(0)
            }
        }
    }

    func streamsSorter(lhs: Stream, rhs: Stream) -> Bool {
        // Use optional chaining to simplify nil handling
        guard let lhsRes = lhs.resolution?.height, let rhsRes = rhs.resolution?.height else {
            return lhs.kind < rhs.kind
        }

        // Compare either kind or resolution based on conditions
        return lhs.kind == rhs.kind ? (lhsRes > rhsRes) : (lhs.kind < rhs.kind)
    }
}
