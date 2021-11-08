import Combine
import Foundation

final class MenuModel: ObservableObject {
    @Published var accounts: AccountsModel? { didSet { registerChildModel(accounts) } }
    @Published var navigation: NavigationModel? { didSet { registerChildModel(navigation) } }
    @Published var player: PlayerModel? { didSet { registerChildModel(player) } }

    private var cancellables = [AnyCancellable]()

    func registerChildModel<T: ObservableObject>(_ model: T?) {
        guard !model.isNil else {
            return
        }

        cancellables.append(model!.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
    }
}
