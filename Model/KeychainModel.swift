import Foundation
import KeychainAccess

struct KeychainModel {
    static var shared = Self()

    var keychain = Keychain(service: "stream.yattee.app")

    func updateAccountKey(_ account: Account, _ key: String, _ value: String) {
        DispatchQueue.global(qos: .background).async {
            keychain[accountKey(account, key)] = value
        }
    }

    func getAccountKey(_ account: Account, _ key: String) -> String? {
        keychain[accountKey(account, key)]
    }

    func accountKey(_ account: Account, _ key: String) -> String {
        "\(account.id)-\(key)"
    }

    func removeAccountKeys(_ account: Account) {
        DispatchQueue.global(qos: .background).async {
            try? keychain.remove(accountKey(account, "token"))
            try? keychain.remove(accountKey(account, "username"))
            try? keychain.remove(accountKey(account, "password"))
        }
    }
}
