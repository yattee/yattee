import Combine
import Defaults
import Foundation

final class AccountsModel: ObservableObject {
    @Published private(set) var current: Instance.Account!

    @Published private(set) var invidious = InvidiousAPI()
    @Published private(set) var piped = PipedAPI()

    private var cancellables = [AnyCancellable]()

    var all: [Instance.Account] {
        Defaults[.accounts]
    }

    var lastUsed: Instance.Account? {
        guard let id = Defaults[.lastAccountID] else {
            return nil
        }

        return AccountsModel.find(id)
    }

    var isEmpty: Bool {
        current.isNil
    }

    var signedIn: Bool {
        !isEmpty && !current.anonymous
    }

    init() {
        cancellables.append(
            invidious.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        )

        cancellables.append(
            piped.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        )
    }

    func setCurrent(_ account: Instance.Account! = nil) {
        guard account != current else {
            return
        }

        current = account

        guard !account.isNil else {
            return
        }

        switch account.instance.app {
        case .invidious:
            invidious.setAccount(account)
        case .piped:
            piped.setAccount(account)
        }

        Defaults[.lastAccountID] = account.anonymous ? nil : account.id
        Defaults[.lastInstanceID] = account.instanceID
    }

    static func find(_ id: Instance.Account.ID) -> Instance.Account? {
        Defaults[.accounts].first { $0.id == id }
    }

    static func add(instance: Instance, name: String, sid: String) -> Instance.Account {
        let account = Instance.Account(instanceID: instance.id, name: name, url: instance.url, sid: sid)
        Defaults[.accounts].append(account)

        return account
    }

    static func remove(_ account: Instance.Account) {
        if let accountIndex = Defaults[.accounts].firstIndex(where: { $0.id == account.id }) {
            Defaults[.accounts].remove(at: accountIndex)
        }
    }
}
