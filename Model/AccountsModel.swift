import Combine
import Defaults
import Foundation

final class AccountsModel: ObservableObject {
    @Published private(set) var account: Instance.Account!

    @Published private(set) var invidious = InvidiousAPI()
    @Published private(set) var piped = PipedAPI()

    private var cancellables = [AnyCancellable]()

    var all: [Instance.Account] {
        Defaults[.instances].map(\.anonymousAccount) + Defaults[.accounts]
    }

    var signedIn: Bool {
        !account.isNil && !account.anonymous
    }

    init() {
        cancellables.append(
            invidious.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        )

        cancellables.append(
            piped.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        )
    }

    func setAccount(_ account: Instance.Account) {
        guard account != self.account else {
            return
        }

        self.account = account

        switch account.instance.app {
        case .invidious:
            invidious.setAccount(account)
        case .piped:
            piped.setAccount(account)
        }
    }
}
