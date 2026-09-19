//
//  DataContextSwitcherMenu.swift
//  Yattee
//
//  The one place the selected data context is switched from.
//

import SwiftUI

// MARK: - Rows

/// The switchable contexts, as rows.
///
/// Shared by every presentation of the switcher so a context that is offered in
/// one place is offered — and named — identically in all of them.
struct DataContextSwitcherRows: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Called after a switch, for presentations that have to close themselves.
    var onSwitch: (() -> Void)?

    private var validator: DataContextValidator? { appEnvironment?.dataContextValidator }

    var body: some View {
        ForEach(validator?.listedContexts ?? [.local], id: \.self) { context in
            row(for: context)
        }
    }

    @ViewBuilder
    private func row(for context: DataContext) -> some View {
        // A menu row is a single label — a `VStack` inside one renders as
        // nothing on macOS — so the status travels in the title rather than as
        // a second line. A context that cannot be switched to says so there
        // too: `title(for:in:)` appends the *display* status, which is what
        // turns a login on a switched-off source into "… — Source switched
        // off" rather than a row that looks ordinary and does nothing.
        let title = DataContextSwitcherLabels.title(for: context, in: appEnvironment)

        #if os(macOS)
        // The mark has to be the menu item's own. A `Label`'s `systemImage` is
        // dropped by a macOS menu row, leaving the selected context
        // indistinguishable from the rest; a `Toggle` is what SwiftUI renders
        // as a checked item, mark character included.
        Toggle(isOn: Binding(
            get: { isCurrent(context) },
            set: { isOn in
                guard isOn else { return }
                switchTo(context)
            }
        )) {
            Text(title)
        }
        .disabled(isRefused(context))
        #else
        Button {
            switchTo(context)
        } label: {
            if isCurrent(context) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .disabled(isRefused(context))
        #endif
    }

    private func switchTo(_ context: DataContext) {
        // The row is disabled as well; this is what makes the refusal true on
        // any presentation where a disabled control can still be activated.
        guard !isRefused(context) else { return }

        appEnvironment?.switchDataContext(to: context)
        onSwitch?()
    }

    private func isCurrent(_ context: DataContext) -> Bool {
        appEnvironment?.accountsManager.currentContext == context
    }

    /// Listed, but not something the user may pick.
    ///
    /// The current context is never refused, whatever its source is doing: it
    /// is already the selection, picking it changes nothing, and a disabled
    /// macOS menu item is not the place to hang the app's only checkmark. It
    /// carries its status in the title instead, which is the part that has to
    /// survive.
    private func isRefused(_ context: DataContext) -> Bool {
        guard let validator, !isCurrent(context) else { return false }
        return !validator.isSwitchable(context)
    }
}

// MARK: - Labels

/// Names the switchable contexts.
enum DataContextSwitcherLabels {
    /// The context's name, plus whatever the user needs to tell it apart.
    @MainActor
    static func title(for context: DataContext, in appEnvironment: AppEnvironment?) -> String {
        guard let appEnvironment else { return String(localized: "subscriptions.account.local.device") }

        return title(
            for: context,
            accountsManager: appEnvironment.accountsManager,
            validator: appEnvironment.dataContextValidator,
            username: { appEnvironment.accountCredentialsManager(for: $0)?.username(for: $0) }
        )
    }

    /// The same label, built from only what it needs.
    ///
    /// Taking the pieces rather than the environment is what lets the naming
    /// rules be exercised on their own: which suffix a name gets depends on the
    /// other accounts, the stored identifier and the host, and on nothing else.
    @MainActor
    static func title(
        for context: DataContext,
        accountsManager: AccountsManager,
        validator: DataContextValidator,
        username: (Account) -> String?
    ) -> String {
        let name = validator.displayName(for: context)

        guard case let .account(id) = context, let account = accountsManager.account(id: id) else {
            return name
        }

        var title = name

        let peers = peers(sharing: name, accountsManager: accountsManager, validator: validator)
        if peers.count > 1 {
            title = disambiguated(
                name,
                for: account,
                among: peers,
                accountsManager: accountsManager,
                username: username
            )
        }

        let status = accountsManager.displayStatus(for: account)
        guard status != .signedIn else { return title }

        return "\(title) — \(AccountStatusBadge.text(for: status))"
    }

    /// What a shared name needs added to it before it names one account.
    ///
    /// The identifier comes first: two logins on the *same* instance share a
    /// host, so a host suffix would repeat the server and still leave the user
    /// choosing between two identical rows. The host — the source's title when
    /// it has one — alone is what is left when the identifier is not on this
    /// device — tvOS never receives one. Neither is repeated when the name
    /// already carries it: the default name for an account *is*
    /// `identifier@host`, so appending it unguarded produced two rows reading
    /// `X · X`.
    ///
    /// The source is the last resort and the only one that can name what two
    /// logins of the same server user on two copies of the same server differ
    /// by — the thing the user chose when adding the second source.
    static func disambiguated(_ name: String, username: String?, host: String?, source: String? = nil) -> String {
        var parts: [String] = []

        if let username, !username.isEmpty, !name.localizedCaseInsensitiveContains(username) {
            if let host, !host.isEmpty, !name.localizedCaseInsensitiveContains(host) {
                parts.append("\(username)@\(host)")
            } else {
                parts.append(username)
            }
        } else if let host, !host.isEmpty, !name.localizedCaseInsensitiveContains(host) {
            parts.append(host)
        }

        if let source, !source.isEmpty, name.localizedCaseInsensitiveCompare(source) != .orderedSame {
            parts.append(source)
        }

        guard !parts.isEmpty else { return name }
        return "\(name) · \(parts.joined(separator: " · "))"
    }

    /// The identifier and the host first, and the source only once they have
    /// failed: two logins on one server are told apart by who they are, and
    /// naming the server as well would add a word that is the same on both
    /// rows. It is when that suffix still collides — the same server user
    /// signed in on two sources pointing at the same host — that the source is
    /// the only thing left that differs.
    @MainActor
    private static func disambiguated(
        _ name: String,
        for account: Account,
        among peers: [Account],
        accountsManager: AccountsManager,
        username: (Account) -> String?
    ) -> String {
        // The same short label the default account name is built from — the
        // source's title, host only as the fallback — or a name that already
        // reads `user@Title` would fail the "already carries it" guard and
        // grow a second, longer `user@full.host` suffix.
        func withoutSource(_ peer: Account) -> String {
            disambiguated(
                name,
                username: username(peer),
                host: accountsManager.instance(for: peer)?.shortLabel
            )
        }

        let own = withoutSource(account)
        let collides = peers.contains { $0.id != account.id && withoutSource($0) == own }
        guard collides else { return own }

        return disambiguated(
            name,
            username: username(account),
            host: accountsManager.instance(for: account)?.shortLabel,
            source: accountsManager.instance(for: account)?.displayName
        )
    }

    @MainActor
    private static func peers(
        sharing name: String,
        accountsManager: AccountsManager,
        validator: DataContextValidator
    ) -> [Account] {
        accountsManager.selectableAccounts.filter { validator.displayName(for: $0) == name }
    }
}

// MARK: - Visibility

/// When the switcher is offered at all.
///
/// One rule for every presentation: no switcher until an account exists to
/// switch to. A user who has never signed in anywhere has only local data, and
/// a menu offering the one context they are already in is chrome with nothing
/// to say. Orphans and accounts still waiting for their instance don't count —
/// neither is a context the switcher would actually list.
enum DataContextSwitcherVisibility {
    /// The settings presentations: the accounts screen and the subscriptions
    /// settings row. Only the existence of an account gates these — they are
    /// where "Show Account Pickers" is explained and turned back on, so the
    /// toggle itself must not hide them.
    @MainActor
    static func showsSwitcher(in appEnvironment: AppEnvironment?) -> Bool {
        guard let appEnvironment else { return false }
        return !appEnvironment.accountsManager.selectableAccounts.isEmpty
    }

    /// Everything outside Settings: the toolbar menus, the tvOS buttons, the
    /// macOS sidebar row. Same account rule, plus the user's toggle.
    @MainActor
    static func showsPickers(in appEnvironment: AppEnvironment?) -> Bool {
        guard let appEnvironment else { return false }
        return appEnvironment.settingsManager.showAccountPickers && showsSwitcher(in: appEnvironment)
    }

    #if os(iOS)
    /// The iOS toolbar menus: same rule again, minus the regular widths, where
    /// the sidebar layout already pins the switcher in its bottom bar — a
    /// toolbar button there would say the same thing twice, the way macOS
    /// toolbars already leave it to the sidebar row.
    @MainActor
    static func showsToolbarPickers(
        in appEnvironment: AppEnvironment?,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        horizontalSizeClass == .compact && showsPickers(in: appEnvironment)
    }
    #endif
}

// MARK: - Glyph

/// How the switcher's icon reads.
///
/// Shared by every presentation of the switcher — the toolbar menu, the
/// settings row, the tvOS button — so the same account health cannot look
/// healthy in one of them and not in another.
enum DataContextSwitcherGlyph {
    /// Whether the icon should ask to be noticed.
    ///
    /// Only the states the user can actually clear: signing in again, turning
    /// the instance back on, or switching away. A context that is merely still
    /// resolving is not one of them — badging `checking` would put an
    /// exclamation mark on every cold launch, before the Keychain has answered.
    static func needsAttention(_ validity: DataContextValidity) -> Bool {
        switch validity {
        case .valid:
            return false
        case .removed:
            return true
        case let .temporarilyUnavailable(reason):
            switch reason {
            case .instanceDisabled, .accountInactive, .credentialRejected, .unreachable: return true
            case .checking, .instancePending, .credentialMissing: return false
            }
        }
    }

    /// The filled glyph says an account is selected; the badge says that
    /// account cannot be used right now, which is the whole reason the user
    /// would reach for this control.
    static func systemImage(for context: DataContext, validity: DataContextValidity) -> String {
        guard !context.isLocal else { return "person.crop.circle" }

        if needsAttention(validity) { return "person.crop.circle.badge.exclamationmark" }
        return "person.crop.circle.fill"
    }

    /// Orange — the colour the settings entry already badges attention with —
    /// and no tint at all otherwise, so a healthy switcher keeps whatever
    /// styling the toolbar or the list gives it.
    static func tint(for context: DataContext, validity: DataContextValidity) -> Color? {
        guard !context.isLocal, needsAttention(validity) else { return nil }
        return .orange
    }

    @MainActor
    static func systemImage(in appEnvironment: AppEnvironment?) -> String {
        guard let appEnvironment else { return "person.crop.circle" }

        return systemImage(
            for: appEnvironment.accountsManager.currentContext,
            validity: appEnvironment.dataContextValidator.validity
        )
    }

    @MainActor
    static func tint(in appEnvironment: AppEnvironment?) -> Color? {
        guard let appEnvironment else { return nil }

        return tint(
            for: appEnvironment.accountsManager.currentContext,
            validity: appEnvironment.dataContextValidator.validity
        )
    }
}

/// The switcher's icon, health included.
///
/// Hidden from assistive technology on purpose: every presentation names the
/// switcher in words beside it, and an unlabelled `Image` announces its symbol
/// — a control that read "Account" while healthy started reading
/// "person.crop.circle.badge.exclamationmark" the moment it badged.
struct DataContextSwitcherIcon: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        let image = Image(systemName: DataContextSwitcherGlyph.systemImage(in: appEnvironment))

        Group {
            if let tint = DataContextSwitcherGlyph.tint(in: appEnvironment) {
                image.foregroundStyle(tint)
            } else {
                image
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Menu

#if !os(tvOS)
/// The toolbar switcher: one tap, no confirmation — switching is reversible.
struct DataContextSwitcherMenu: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Menu {
            DataContextSwitcherRows()
        } label: {
            Label {
                Text(String(localized: "accounts.switcher.title"))
            } icon: {
                DataContextSwitcherIcon()
            }
        }
        .help(contextTitle)
        .accessibilityLabel(Text(String(localized: "accounts.switcher.title")))
        .accessibilityValue(Text(contextTitle))
    }

    private var contextTitle: String {
        DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment)
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }
}

#endif

#if os(iOS)
/// The iPad sidebar pill's presentation: just the icon and the current
/// account's name, centered. The pill's placement already says what the
/// control is, so the "Account" caption the settings rows carry is dropped;
/// assistive technology still gets it as the label.
struct DataContextSwitcherSidebarRow: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Menu {
            DataContextSwitcherRows()
        } label: {
            HStack(spacing: 6) {
                DataContextSwitcherIcon()
                Text(contextTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // The sidebar bottom bar hosts the menu's label in a UIKit button that
        // keeps its first rendering: switching accounts moved the checkmark
        // but the pill kept naming the old context. Recreating the menu when
        // the name changes is the part SwiftUI won't do on its own here.
        .id(contextTitle)
        .accessibilityLabel(Text(String(localized: "accounts.switcher.title")))
        .accessibilityValue(Text(contextTitle))
    }

    private var contextTitle: String {
        DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment)
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }
}
#endif

/// A settings row naming the current context, with the switcher attached.
struct DataContextSwitcherSettingsRow: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        #if os(tvOS)
        // The same menu the Subscriptions, History and Playlists headers use:
        // one click, options in place, rather than a full-screen round trip.
        Menu {
            DataContextSwitcherRows()
        } label: {
            rowLabel
        }
        #elseif os(macOS)
        // A macOS menu label renders its first text and nothing else — the
        // trailing name was dropped at every width, leaving the row silent
        // about which account is selected. So the name is the menu's *own*
        // label, and the row carries only what names the control.
        // `LabeledContent` overflows rather than compress its label, so at the
        // sidebar's 140 pt minimum a captioned row (caption + spacing + the
        // name's floor ≈ 158 pt) juts past both edges. The caption is the one
        // part the icon already says, so it is the part that goes.
        ViewThatFits(in: .horizontal) {
            macOSRow(captioned: true)
            macOSRow(captioned: false)
        }
        #else
        Menu {
            DataContextSwitcherRows()
        } label: {
            rowLabel
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder private func macOSRow(captioned: Bool) -> some View {
        LabeledContent {
            Menu {
                DataContextSwitcherRows()
            } label: {
                Text(contextTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            // The floor must sit on the menu itself: a borderless menu button
            // lays out its label alone, so a frame inside it never reaches the
            // row's layout, and the caption would keep its ideal width while
            // the name shrank to an ellipsis. Out here the menu claims the
            // width and the caption is what gives way.
            .frame(minWidth: Self.minimumNameWidth, alignment: .trailing)
            .layoutPriority(1)
            .help(contextTitle)
            .accessibilityLabel(Text(String(localized: "accounts.switcher.title")))
            .accessibilityValue(Text(contextTitle))
        } label: {
            Label {
                if captioned {
                    Text(String(localized: "accounts.switcher.title"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } icon: {
                DataContextSwitcherIcon()
            }
        }
    }
    #endif

    /// What the trailing name may never be squeezed below.
    ///
    /// A row this narrow — the macOS sidebar's footer at a dragged-in column
    /// width — hands the leading label its ideal width first and leaves the
    /// name whatever is left, and a `Text` will shrink all the way to a lone
    /// ellipsis before it complains. A floor turns that around: the name keeps
    /// enough characters to be recognised, and the word naming the control —
    /// which the icon beside it already says — is what truncates instead.
    private static let minimumNameWidth: CGFloat = 80

    #if !os(macOS)
    private var rowLabel: some View {
        HStack {
            Label {
                Text(String(localized: "accounts.switcher.title"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                DataContextSwitcherIcon()
            }
            Spacer(minLength: 8)
            Text(contextTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: Self.minimumNameWidth, alignment: .trailing)
        }
    }
    #endif

    private var contextTitle: String {
        DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment)
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }
}

// MARK: - tvOS button

#if os(tvOS)
/// The switcher for placing beside other tvOS controls: a menu, like the
/// menu-style pickers in Settings, so switching is one click instead of a
/// full-screen round trip.
struct DataContextSwitcherButton: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Menu {
            DataContextSwitcherRows()
        } label: {
            Label {
                // One line always: beside other header buttons the name would
                // wrap into a tall two-line lozenge before it truncates.
                Text(DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                DataContextSwitcherIcon()
            }
        }
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }
}
#endif
