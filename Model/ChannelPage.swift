import Foundation

struct ChannelPage {
    var results = [ContentItem]()
    var channel: Channel?
    var nextPage: String?
    var last = false
}
