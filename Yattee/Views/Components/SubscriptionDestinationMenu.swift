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

// MARK: - Loading

/// Asks every destination whether the channel is subscribed there, and holds
/// the answers the rows render.
///
/// Deliberately owned by the view that *presents* the rows rather than by the
/// rows themselves. A `Menu`'s content is handed to the platform's own menu —
/// an `NSMenu` on macOS — and SwiftUI runs no lifecycle inside one: `.task`,
/// `.onAppear` and `.onReceive` attached to rows there are never called. A
/// round asked for from inside the menu is a round that never happens, leaving
/// every row unknown; unknown reads as "not subscribed", so each row would
/// subscribe again instead of doing the unsubscribe it promises.
@MainActor
@Observable
final class SubscriptionDestinationMembershipLoader {
    private(set) var membership = SubscriptionDestinationMembership()

    /// Destinations with a write in flight.
    private(set) var busy: Set<DataContext> = []

    @ObservationIgnored private weak var appEnvironment: AppEnvironment?
    @ObservationIgnored private var channel: Channel?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init() {
        // The credential behind an account was replaced, the accounts
        // themselves changed, or an instance was switched back on and added a
        // destination on the spot: every answer held here describes the logins
        // that were there before.
        for name: Notification.Name in [.accountCredentialDidChange, .accountsDidChange, .instancesDidChange] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.reload() }
                }
            )
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func isSubscribed(on context: DataContext) -> Bool? { membership.isSubscribed(on: context) }

    func isBusy(_ context: DataContext) -> Bool { busy.contains(context) }

    /// Asks about `channel`, from a place the SwiftUI lifecycle reaches.
    ///
    /// Answered before the menu is opened rather than while it is open: a
    /// platform menu is built from the values it is handed, so a mark that
    /// arrives afterwards is a mark the user does not see.
    func load(for channel: Channel, in appEnvironment: AppEnvironment?) async {
        self.channel = channel
        self.appEnvironment = appEnvironment

        reloadTask?.cancel()
        await ask()
    }

    /// Forgets what is known and asks again.
    ///
    /// Forgetting first, rather than waiting for the replacement answers: a row
    /// toggled in between would otherwise toggle against the previous login's
    /// membership and do the opposite of what its mark promises.
    private func reload() {
        guard channel != nil else { return }

        membership.invalidate()
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in await self?.ask() }
    }

    private func ask() async {
        guard let channel, let service = appEnvironment?.subscriptionService else { return }

        membership.invalidate()
        let generation = membership.generation
        let channelID = channel.id.channelID

        // Serially rather than in a group: each cold destination answers by
        // fetching its account's whole list, and firing every instance at once
        // is a burst the user never asked for.
        for context in SubscriptionDestinations.available(in: appEnvironment) {
            let subscribed = await service.isSubscribed(to: channelID, in: context)
            membership.record(subscribed, for: context, generation: generation)
        }
    }

    // MARK: - Toggle

    func toggle(
        _ context: DataContext,
        of channel: Channel,
        in appEnvironment: AppEnvironment?,
        onToggled: ((DataContext, Bool) -> Void)?
    ) {
        guard let appEnvironment else { return }

        self.channel = channel
        self.appEnvironment = appEnvironment

        // Unknown counts as not subscribed: the row carries no mark, so
        // subscribing is what the user just asked for. Asking the server again
        // at press time would be the other way round — it could unsubscribe
        // under a row that showed no mark at all.
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

                // A menu closes on the press that made the write, so the mark
                // the row will carry on its next open is not something the user
                // is looking at. The toast is what tells them it landed, and
                // where — the main button speaks for the account being browsed,
                // which a destination write usually is not.
                appEnvironment.toastManager.showSuccess(
                    String(
                        localized: wasSubscribed
                            ? "channel.subscribe.destination.unsubscribed"
                            : "channel.subscribe.destination.subscribed"
                    ),
                    subtitle: DataContextSwitcherLabels.title(for: context, in: appEnvironment)
                )
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

    /// What is known about the destinations, asked for outside the menu.
    let membership: SubscriptionDestinationMembershipLoader

    /// The destination that was toggled and whether it is now subscribed, for
    /// the view that owns the main subscribe button.
    var onToggled: ((DataContext, Bool) -> Void)?

    /// Called after any tap, for presentations that have to close themselves.
    var onSelect: (() -> Void)?

    var body: some View {
        ForEach(destinations, id: \.self) { context in
            row(for: context)
        }
    }

    @ViewBuilder
    private func row(for context: DataContext) -> some View {
        let title = DataContextSwitcherLabels.title(for: context, in: appEnvironment)

        #if os(tvOS)
        Button {
            toggle(context)
            onSelect?()
        } label: {
            if membership.isSubscribed(on: context) == true {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .buttonStyle(TVSettingsButtonStyle())
        .disabled(isRefusing(context))
        #else
        // The mark is the menu's own, not a drawn glyph: an image inside a
        // macOS menu row is dropped, and a toggle is what both platforms render
        // — and report to VoiceOver — as a checked row.
        Toggle(isOn: subscribed(on: context)) {
            Text(title)
        }
        .disabled(isRefusing(context))
        #endif
    }

    private func subscribed(on context: DataContext) -> Binding<Bool> {
        Binding(
            get: { membership.isSubscribed(on: context) == true },
            set: { _ in
                toggle(context)
                onSelect?()
            }
        )
    }

    private var destinations: [DataContext] {
        SubscriptionDestinations.available(in: appEnvironment)
    }

    /// Whether the destination would refuse the write it is offering.
    ///
    /// The same gate the main subscribe button uses, asked about the row's own
    /// target rather than the account being browsed. A rejected or unreachable
    /// account is listed — it names its state, and hiding it would read as a
    /// login that had been deleted — but pressing it can only cost a doomed
    /// request and an error toast, so it is not pressable.
    private func isRefusing(_ context: DataContext) -> Bool {
        if membership.isBusy(context) { return true }
        guard let appEnvironment else { return !context.isLocal }
        return !appEnvironment.dataContextValidator.validity(of: context).isValid
    }

    private func toggle(_ context: DataContext) {
        membership.toggle(context, of: channel, in: appEnvironment, onToggled: onToggled)
    }
}

// MARK: - Menu

#if !os(tvOS)
/// The destination submenu, for placing inside the channel menu.
struct SubscriptionDestinationMenu: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let channel: Channel
    let membership: SubscriptionDestinationMembershipLoader
    var onToggled: ((DataContext, Bool) -> Void)?

    var body: some View {
        if SubscriptionDestinations.areOffered(in: appEnvironment) {
            Menu {
                SubscriptionDestinationRows(
                    channel: channel,
                    membership: membership,
                    onToggled: onToggled
                )
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
    let membership: SubscriptionDestinationMembershipLoader
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
                        SubscriptionDestinationRows(
                            channel: channel,
                            membership: membership,
                            onToggled: onToggled
                        )
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
