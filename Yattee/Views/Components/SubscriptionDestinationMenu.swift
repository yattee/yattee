//
//  SubscriptionDestinationMenu.swift
//  Yattee
//
//  Subscribing somewhere other than the account currently being browsed.
//

import SwiftUI

// MARK: - Membership

/// What is known about a channel's subscription on each destination.
///
/// "Not asked yet" and "asked, not subscribed" are different rows, so the
/// unknown state is kept rather than collapsed into `false`. Answers carry the
/// round they were asked under: a channel change or a second look at the menu
/// starts a new round, and a reply from the old one is dropped instead of being
/// shown against the wrong channel.
struct SubscriptionDestinationMembership: Equatable {
    private var known: [DataContext: Bool] = [:]
    private(set) var generation = 0

    /// Forgets every answer and opens a new round.
    mutating func invalidate() {
        known.removeAll()
        generation += 1
    }

    /// Records an answer from `generation`.
    ///
    /// A `nil` answer says nothing — the destination has no provider, or the
    /// logins were replaced while it was in flight — and must not be stored as
    /// "not subscribed".
    mutating func record(_ isSubscribed: Bool?, for context: DataContext, generation: Int) {
        guard generation == self.generation, let isSubscribed else { return }
        known[context] = isSubscribed
    }

    /// nil while nothing is known, which renders as neither state.
    func isSubscribed(on context: DataContext) -> Bool? { known[context] }
}

// MARK: - Destinations

/// Where a channel can be subscribed.
enum SubscriptionDestinations {
    /// Local plus every account a subscribe could actually land on.
    ///
    /// The same three things the write layer insists on — the backend must do
    /// subscriptions, the instance must be one this app still talks to, and
    /// there must be a credential to talk with. Account *status* deliberately
    /// is not among them: a stale "rejected" would hide a login that works, and
    /// a failed write says so with a toast. Neither is the selected context's
    /// availability — a row names its own target, so it keeps working when the
    /// account being browsed cannot be reached.
    @MainActor
    static func available(in appEnvironment: AppEnvironment?) -> [DataContext] {
        guard let appEnvironment else { return [.local] }

        let accounts = appEnvironment.accountsManager.accounts.filter { account in
            appEnvironment.accountsManager.capabilities(for: account)?.supportsSubscriptions == true
                && appEnvironment.accountsManager.instance(for: account)?.isEnabled == true
                && appEnvironment.accountCredentialsManager(for: account)?.isLoggedIn(for: account) == true
        }

        return [.local] + accounts.map { DataContext.account($0.id) }
    }

    /// Whether naming a destination is a choice worth offering.
    ///
    /// With only local to offer there is normally nothing the main subscribe
    /// button does not already do — unless that button is refusing, because the
    /// selected account cannot be written to. Local is then exactly the
    /// alternative the user is looking for.
    @MainActor
    static func areOffered(in appEnvironment: AppEnvironment?) -> Bool {
        if available(in: appEnvironment).count > 1 { return true }

        guard let appEnvironment else { return false }
        return !appEnvironment.accountsManager.currentContext.isLocal
            && !appEnvironment.dataContextValidator.allowsServerMutations
    }
}

// MARK: - Rows

/// One row per place the channel can be subscribed, with the membership known
/// there.
///
/// Shared by the menu and the tvOS picker so a destination that is offered in
/// one is offered — and toggled — identically in the other.
struct SubscriptionDestinationRows: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// The channel as it must be stored, with the id the calling view resolved.
    let channel: Channel

    /// The destination that was toggled and whether it is now subscribed, for
    /// the view that owns the main subscribe button.
    var onToggled: ((DataContext, Bool) -> Void)?

    /// Called after any tap, for presentations that have to close themselves.
    var onSelect: (() -> Void)?

    @State private var membership = SubscriptionDestinationMembership()
    @State private var busy: Set<DataContext> = []
    /// Bumped when the logins change, so the answers are asked for again.
    @State private var membershipRound = 0

    /// What a round of membership answers belongs to.
    ///
    /// The channel alone is not enough: the same channel on the same rows means
    /// something different once a credential has been replaced, and the picker
    /// deliberately stays open across such a change on tvOS.
    private struct MembershipRequest: Equatable {
        let channel: Channel.ID
        let round: Int
    }

    var body: some View {
        ForEach(destinations, id: \.self) { context in
            Button {
                toggle(context)
                onSelect?()
            } label: {
                rowLabel(for: context)
            }
            .disabled(busy.contains(context))
            #if os(tvOS)
            .buttonStyle(TVSettingsButtonStyle())
            #endif
        }
        // Membership is only asked for once the rows are on screen: an unwarmed
        // provider answers by fetching that account's whole subscription list,
        // which is far too much to spend on a menu nobody opened.
        .task(id: MembershipRequest(channel: channel.id, round: membershipRound)) {
            await loadMembership()
        }
        // The credential behind an account was replaced, or the accounts
        // themselves changed: every checkmark on screen describes the logins
        // that were there before.
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            invalidateMembership()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountsDidChange)) { _ in
            invalidateMembership()
        }
        // An instance switched on adds a row to `destinations` on the spot, and
        // the round that would have asked about it has already run. Unknown
        // reads as unsubscribed, so an account the channel is already on gets a
        // checkmark-less row whose tap subscribes again instead of doing the
        // unsubscribe it promises.
        .onReceive(NotificationCenter.default.publisher(for: .instancesDidChange)) { _ in
            invalidateMembership()
        }
    }

    /// Forgets what is known and asks again.
    ///
    /// Forgetting first, rather than waiting for the replacement answers: a row
    /// toggled in between would otherwise toggle against the previous login's
    /// membership and do the opposite of what its checkmark promises.
    private func invalidateMembership() {
        membership.invalidate()
        membershipRound += 1
    }

    @ViewBuilder
    private func rowLabel(for context: DataContext) -> some View {
        let title = DataContextSwitcherLabels.title(for: context, in: appEnvironment)

        if membership.isSubscribed(on: context) == true {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var destinations: [DataContext] {
        SubscriptionDestinations.available(in: appEnvironment)
    }

    // MARK: - Membership

    private func loadMembership() async {
        guard let service = appEnvironment?.subscriptionService else { return }

        membership.invalidate()
        let generation = membership.generation
        let channelID = channel.id.channelID

        // Serially rather than in a group: each cold destination answers by
        // fetching its account's whole list, and firing every instance at once
        // is a burst the user never asked for.
        for context in destinations {
            let subscribed = await service.isSubscribed(to: channelID, in: context)
            membership.record(subscribed, for: context, generation: generation)
        }
    }

    // MARK: - Toggle

    private func toggle(_ context: DataContext) {
        guard let appEnvironment else { return }

        // Unknown counts as not subscribed: the row shows no checkmark, so
        // subscribing is what the user just asked for.
        let wasSubscribed = membership.isSubscribed(on: context) == true
        let generation = membership.generation
        let channelID = channel.id.channelID

        busy.insert(context)

        Task {
            do {
                if wasSubscribed {
                    try await appEnvironment.subscriptionService.unsubscribe(from: channelID, in: context)
                } else {
                    try await appEnvironment.subscriptionService.subscribe(to: channel, in: context)
                }

                membership.record(!wasSubscribed, for: context, generation: generation)
                onToggled?(context, !wasSubscribed)
            } catch {
                appEnvironment.toastManager.showError(
                    String(
                        localized: wasSubscribed
                            ? "channel.unsubscribe.error.title"
                            : "channel.subscribe.error.title"
                    ),
                    subtitle: error.localizedDescription
                )
            }

            busy.remove(context)
        }
    }
}

// MARK: - Menu

#if !os(tvOS)
/// The destination submenu, for placing inside the channel menu.
struct SubscriptionDestinationMenu: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let channel: Channel
    var onToggled: ((DataContext, Bool) -> Void)?

    var body: some View {
        if SubscriptionDestinations.areOffered(in: appEnvironment) {
            Menu {
                SubscriptionDestinationRows(channel: channel, onToggled: onToggled)
            } label: {
                Label(
                    String(localized: "channel.menu.subscribeOn"),
                    systemImage: "person.crop.circle.badge.plus"
                )
            }
        }
    }
}
#endif

// MARK: - tvOS picker

#if os(tvOS)
/// The tvOS destination list, presented in a `fullScreenCover`: menus are
/// unusable there, and a sheet is a card too small to read.
struct SubscriptionDestinationPicker: View {
    @Environment(\.dismiss) private var dismiss

    let channel: Channel
    var onToggled: ((DataContext, Bool) -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "channel.menu.subscribeOn"))
                    .font(.title2.bold())

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // The picker stays open across a toggle: checkmarks are
                        // the whole point of the list, and closing it would hide
                        // the change the user just made.
                        SubscriptionDestinationRows(channel: channel, onToggled: onToggled)
                    }
                }

                Button(String(localized: "common.close")) {
                    dismiss()
                }
                .buttonStyle(TVSettingsButtonStyle())
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
    }
}
#endif
