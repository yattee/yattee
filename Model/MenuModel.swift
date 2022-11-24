import Combine
import Foundation

final class MenuModel: ObservableObject {
    static let shared = MenuModel()
    private var cancellables = [AnyCancellable]()

    init() {
        registerChildModel(AccountsModel.shared)
        registerChildModel(NavigationModel.shared)
        registerChildModel(PlayerModel.shared)
    }

    func registerChildModel<T: ObservableObject>(_ model: T?) {
        guard !model.isNil else {
            return
        }

        cancellables.append(model!.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
    }
}
