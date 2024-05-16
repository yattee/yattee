import Alamofire
import Defaults
import Foundation
import Logging
import SwiftyJSON

final class SponsorBlockAPI: ObservableObject {
    static let categories = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "filler", "music_offtopic"]

    let logger = Logger(label: "stream.yattee.app.sb")

    @Published var videoID: String?
    @Published var segments = [Segment]()

    static func categoryDescription(_ name: String) -> String? {
        guard categories.contains(name) else {
            return nil
        }

        switch name {
        case "sponsor":
            return "Sponsor".localized()
        case "selfpromo":
            return "Unpaid/Self Promotion".localized()
        case "interaction":
            return "Interaction Reminder (Subscribe)".localized()
        case "intro":
            return "Intermission/Intro Animation".localized()
        case "outro":
            return "Endcards/Credits".localized()
        case "preview":
            return "Preview/Recap/Hook".localized()
        case "filler":
            return "Filler Tangent/Jokes".localized()
        case "music_offtopic":
            return "Music: Non-Music Section".localized()
        default:
            return name.capitalized
        }
    }

    static func categoryDetails(_ name: String) -> String? {
        guard categories.contains(name) else {
            return nil
        }

        switch name {
        case "sponsor":
            return ("Part of a video promoting a product or service not directly related to the creator. " +
                "The creator will receive payment or compensation in the form of money or free products.").localized()

        case "selfpromo":
            return ("The creator will not receive any payment in exchange for this promotion. " +
                "This includes charity drives or free shout outs for products or other people they like.\n\n" +
                "Promoting a product or service that is directly related to the creator themselves. " +
                "This usually includes merchandise or promotion of monetized platforms.").localized()

        case "interaction":
            return "Explicit reminders to like, subscribe or interact with them on any paid or free platform(s) (e.g. click on a video).".localized()

        case "intro":
            return ("Segments typically found at the start of a video that include an animation, " +
                "still frame or clip which are also seen in other videos by the same creator.").localized()

        case "outro":
            return "Typically near or at the end of the video when the credits pop up and/or endcards are shown.".localized()

        case "preview":
            return "Collection of clips that show what is coming up in in this video or other videos in a series where all information is repeated later in the video".localized()

        case "filler":
            return "Filler Tangent/ Jokes is only for tangential scenes added only for filler or humor that are not required to understand the main content of the video.".localized()

        case "music_offtopic":
            return "For videos which feature music as the primary content.".localized()

        default:
            return nil
        }
    }

    func loadSegments(videoID: String, categories: Set<String>, completionHandler: @escaping () -> Void = {}) {
        guard !skipSegmentsURL.isNil, self.videoID != videoID else {
            completionHandler()
            return
        }

        self.videoID = videoID

        DispatchQueue.main.async { [weak self] in
            self?.requestSegments(categories: categories, completionHandler: completionHandler)
        }
    }

    func reset() {
        videoID = nil
        segments = []
    }

    private func requestSegments(categories: Set<String>, completionHandler: @escaping () -> Void = {}) {
        guard let url = skipSegmentsURL, !categories.isEmpty else {
            return
        }

        AF.request(url, parameters: parameters(categories: categories)).responseDecodable(of: JSON.self) { [weak self] response in
            guard let self else {
                return
            }

            switch response.result {
            case let .success(value):
                self.segments = JSON(value).arrayValue.map(SponsorBlockSegment.init).sorted { $0.end < $1.end }

                self.logger.info("loaded \(self.segments.count) SponsorBlock segments")
                for segment in self.segments {
                    self.logger.info("\(segment.start) -> \(segment.end)")
                }
            case let .failure(error):
                self.segments = []

                self.logger.error("failed to load SponsorBlock segments: \(error.localizedDescription)")
            }

            completionHandler()
        }
    }

    private var skipSegmentsURL: String? {
        let url = Defaults[.sponsorBlockInstance]
        return url.isEmpty ? nil : "\(url)/api/skipSegments"
    }

    private func parameters(categories: Set<String>) -> [String: String] {
        [
            "videoID": videoID!,
            "categories": JSON(Array(categories)).rawString(String.Encoding.utf8)!
        ]
    }
}
