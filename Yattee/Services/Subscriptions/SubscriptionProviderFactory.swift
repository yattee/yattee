//
//  SubscriptionProviderFactory.swift
//  Yattee
//
//  Builds the provider that serves one account's subscriptions.
//

import Foundation

/// Makes the provider for an account.
///
/// A seam rather than a switch inside `SubscriptionService`: the provider is
/// what a destination write actually lands on, so which one a context resolves
/// to has to be observable without a server behind it.
@MainActor
protocol SubscriptionProviderFactory {
    /// The provider for an account on a resolved, subscription-capable
    /// instance, or nil when the backend has no subscriptions API.
    func provider(
        for account: Account,
        instance: Instance,
        accountsManager: AccountsManager
    ) -> (any SubscriptionProvider)?
}

/// The app's factory: one provider per backend that has an accounts API.
@MainActor
struct DefaultSubscriptionProviderFactory: SubscriptionProviderFactory {
    let invidiousAPI: InvidiousAPI
    let pipedAPI: PipedAPI
    let invidiousCredentialsManager: InvidiousCredentialsManager
    let pipedCredentialsManager: PipedCredentialsManager
    let settingsManager: SettingsManager

    func provider(
        for account: Account,
        instance: Instance,
        accountsManager: AccountsManager
    ) -> (any SubscriptionProvider)? {
        switch instance.type {
        case .invidious:
            return InvidiousSubscriptionProvider(
                account: account,
                invidiousAPI: invidiousAPI,
                credentialsManager: invidiousCredentialsManager,
                accountsManager: accountsManager,
                settingsManager: settingsManager
            )
        case .piped:
            return PipedSubscriptionProvider(
                account: account,
                pipedAPI: pipedAPI,
                credentialsManager: pipedCredentialsManager,
                accountsManager: accountsManager,
                settingsManager: settingsManager
            )
        default:
            return nil
        }
    }
}
