//
//  InstanceDeletionDisclosure.swift
//  Yattee
//
//  What deleting a source takes with it, said before it happens.
//

import Foundation

/// Names the accounts an instance deletion would sign out and remove.
///
/// The cascade has always taken them; only the confirmation was silent about
/// it. Deleting a source the user set up months ago is otherwise the one action
/// in the app that quietly destroys a login.
enum InstanceDeletionDisclosure {
    /// The accounts paragraph for the confirmation, or `nil` when the instance
    /// has none and the plain "delete this?" question already says everything.
    static func message(accountNames: [String]) -> String? {
        guard !accountNames.isEmpty else { return nil }

        let warning = String(localized: "sources.delete.accountsWarning \(accountNames.count)")
        return ([warning] + accountNames).joined(separator: "\n")
    }

    @MainActor
    static func message(for instance: Instance, in appEnvironment: AppEnvironment?) -> String? {
        guard let appEnvironment else { return nil }

        let names = appEnvironment.accountsManager
            .accounts(forInstance: instance.id)
            .map { appEnvironment.dataContextValidator.displayName(for: $0) }

        return message(accountNames: names)
    }
}
