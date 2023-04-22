import Foundation
import SwiftUI

final class UnwatchedFeedCountModel: ObservableObject {
    static let shared = UnwatchedFeedCountModel()

    @Published var unwatched = [Account: Int]()
    @Published var unwatchedByChannel = [Account: [Channel.ID: Int]]()

    private var accounts = AccountsModel.shared

    // swiftlint:disable empty_count
    var unwatchedText: Text? {
        if let account = accounts.current,
           !account.anonymous,
           let count = unwatched[account],
           count > 0
        {
            return Text(String(count))
        }

        return nil
    }

    func unwatchedByChannelText(_ channel: Channel) -> Text? {
        if let account = accounts.current,
           !account.anonymous,
           let count = unwatchedByChannel[account]?[channel.id],
           count > 0
        {
            return Text(String(count))
        }
        return nil
    }
    // swiftlint:enable empty_count
}
