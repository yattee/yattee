import Combine
import Foundation

final class MenuModel: ObservableObject {
    static let shared = MenuModel()
    private var cancellables = Set<AnyCancellable>()

    init() {
        registerChildModel(AccountsModel.shared)
        registerChildModel(NavigationModel.shared)
        registerChildModel(PlayerModel.shared)
    }

    func registerChildModel<T: ObservableObject>(_ model: T?) {
        guard let model else {
            return
        }

        model.objectWillChange
            .receive(on: DispatchQueue.main) // Ensure the update occurs on the main thread
            .debounce(for: .milliseconds(10), scheduler: DispatchQueue.main) // Debounce to avoid immediate feedback loops
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
