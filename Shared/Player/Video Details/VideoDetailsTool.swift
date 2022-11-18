import Defaults
import Foundation

struct VideoDetailsTool: Identifiable {
    static let all = [
        Self(icon: "info.circle", name: "Info", page: .info),
        Self(icon: "wand.and.stars", name: "Inspector", page: .inspector),
        Self(icon: "bookmark", name: "Chapters", page: .chapters),
        Self(icon: "text.bubble", name: "Comments", page: .comments),
        Self(icon: "rectangle.stack.fill", name: "Related", page: .related),
        Self(icon: "list.number", name: "Queue", page: .queue)
    ]

    static func find(for page: VideoDetails.DetailsPage) -> Self? {
        all.first { $0.page == page }
    }

    var id: String {
        page.rawValue
    }

    var icon: String
    var name: String
    var toolPostion: CGRect = .zero
    var page = VideoDetails.DetailsPage.info

    func isAvailable(for video: Video?, sidebarQueue: Bool) -> Bool {
        guard !YatteeApp.isForPreviews else {
            return true
        }
        switch page {
        case .info:
            return video != nil && !video!.isLocal
        case .inspector:
            return video == nil || Defaults[.showInspector] == .always || video!.isLocal
        case .chapters:
            return video != nil && !video!.chapters.isEmpty
        case .comments:
            return video != nil && !video!.isLocal
        case .related:
            return !sidebarQueue && video != nil && !video!.isLocal
        case .queue:
            return !sidebarQueue
        }
    }
}
