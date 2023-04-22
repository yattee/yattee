import Foundation

final class AccountsViewModel: ObservableObject {
    typealias AreInIncreasingOrder = (Account, Account) -> Bool

    var accounts: [Account] { AccountsModel.shared.all }

    var sortedAccounts: [Account] {
        accounts.sorted { lhs, rhs in
            let predicates: [AreInIncreasingOrder] = [
                { ($0.app ?? .local).rawValue < ($1.app ?? .local).rawValue },
                { $0.urlHost < $1.urlHost },
                { $0.description < $1.description }
            ]

            for predicate in predicates {
                if !predicate(lhs, rhs), !predicate(rhs, lhs) {
                    continue
                }

                return predicate(lhs, rhs)
            }

            return false
        }
    }

    var publicAccount: Account? { AccountsModel.shared.publicAccount }
    var currentAccount: Account? { AccountsModel.shared.current }

    var instances: [Instance] { InstancesModel.shared.all }
}
