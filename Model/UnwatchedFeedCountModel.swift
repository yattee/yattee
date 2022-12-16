import Foundation
import SwiftUI

final class UnwatchedFeedCountModel: ObservableObject {
    static let shared = UnwatchedFeedCountModel()

    @Published var unwatched = [Account: Int]()
    @Published var unwatchedByChannel = [Account: [Channel.ID: Int]]()

    private var accounts = AccountsModel.shared

    var unwatchedText: Text? {
        if let account = accounts.current,
           !account.anonymous,
           let count = unwatched[account]
        {
            return Text(String(count))
        }

        return nil
    }

    func unwatchedByChannelText(_ channel: Channel) -> Text? {
        if let account = accounts.current,
           !account.anonymous,
           let count = unwatchedByChannel[account]?[channel.id]
        {
            return Text(String(count))
        }
        return nil
    }
}
