//
//  DataContextSwitcherMenu.swift
//  Yattee
//
//  The one place the selected data context is switched from.
//

import SwiftUI

// MARK: - Rows

/// The switchable contexts, as buttons.
///
/// Shared by every presentation of the switcher so a context that is offered in
/// one place is offered — and named — identically in all of them.
struct DataContextSwitcherRows: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Called after a switch, for presentations that have to close themselves.
    var onSwitch: (() -> Void)?

    private var validator: DataContextValidator? { appEnvironment?.dataContextValidator }

    var body: some View {
        ForEach(validator?.availableContexts ?? [.local], id: \.self) { context in
            Button {
                appEnvironment?.switchDataContext(to: context)
                onSwitch?()
            } label: {
                rowLabel(for: context)
            }
            #if os(tvOS)
            .buttonStyle(TVSettingsButtonStyle())
            #endif
        }
    }

    @ViewBuilder
    private func rowLabel(for context: DataContext) -> some View {
        let title = DataContextSwitcherLabels.title(for: context, in: appEnvironment)

        // A menu row is a single label on macOS — a `VStack` inside one renders
        // as nothing there — so the status travels in the title rather than as
        // a second line.
        if isCurrent(context) {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func isCurrent(_ context: DataContext) -> Bool {
        appEnvironment?.accountsManager.currentContext == context
    }
}

// MARK: - Labels

/// Names the switchable contexts.
enum DataContextSwitcherLabels {
    /// The context's name, plus whatever the user needs to tell it apart.
    ///
    /// The host is appended only when several accounts share a display name:
    /// two logins on the same instance are told apart by their username, and a
    /// name that already carries the host would otherwise repeat it.
    @MainActor
    static func title(for context: DataContext, in appEnvironment: AppEnvironment?) -> String {
        guard let appEnvironment else { return String(localized: "subscriptions.account.local") }

        let name = appEnvironment.dataContextValidator.displayName(for: context)

        guard case let .account(id) = context, let account = appEnvironment.accountsManager.account(id: id) else {
            return name
        }

        var title = name

        if isAmbiguous(name, in: appEnvironment),
           let host = appEnvironment.accountsManager.instance(for: account)?.url.host,
           !name.localizedCaseInsensitiveContains(host) {
            title = "\(name) · \(host)"
        }

        let status = appEnvironment.accountsManager.status(for: id)
        guard status != .signedIn else { return title }

        return "\(title) — \(AccountStatusBadge.text(for: status))"
    }

    @MainActor
    private static func isAmbiguous(_ name: String, in appEnvironment: AppEnvironment) -> Bool {
        appEnvironment.accountsManager.selectableAccounts
            .filter { appEnvironment.dataContextValidator.displayName(for: $0) == name }
            .count > 1
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
            Label(String(localized: "accounts.switcher.title"), systemImage: icon)
        }
        .help(DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment))
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }

    /// The filled glyph says an account is selected; the badge says that
    /// account cannot be used right now, which is the whole reason the user
    /// would reach for this control.
    private var icon: String {
        guard !currentContext.isLocal else { return "person.crop.circle" }

        if appEnvironment?.dataContextValidator.unavailability != nil {
            return "person.crop.circle.badge.exclamationmark"
        }
        return "person.crop.circle.fill"
    }
}

#endif

/// A settings row naming the current context, with the switcher attached.
struct DataContextSwitcherSettingsRow: View {
    @Environment(\.appEnvironment) private var appEnvironment
    #if os(tvOS)
    @State private var showingPicker = false
    #endif

    var body: some View {
        #if os(tvOS)
        Button {
            showingPicker = true
        } label: {
            rowLabel
        }
        .buttonStyle(TVSettingsButtonStyle())
        .fullScreenCover(isPresented: $showingPicker) {
            DataContextSwitcherPicker()
        }
        #else
        Menu {
            DataContextSwitcherRows()
        } label: {
            rowLabel
        }
        #if os(macOS)
        // Both callers are full-width rows, so the default style's stretching
        // is wanted here — only its chrome is not.
        .menuStyle(.borderlessButton)
        #endif
        #endif
    }

    private var rowLabel: some View {
        HStack {
            Label(String(localized: "accounts.switcher.title"), systemImage: "person.crop.circle")
            Spacer(minLength: 8)
            Text(DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }
}

// MARK: - tvOS picker

#if os(tvOS)
/// The tvOS switcher, presented in a `fullScreenCover`: menus are unusable
/// there, and a sheet is a card too small to read.
struct DataContextSwitcherPicker: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "accounts.switcher.title"))
                    .font(.title2.bold())

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DataContextSwitcherRows {
                            dismiss()
                        }
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

/// The button that presents the picker, for placing beside other tvOS controls.
struct DataContextSwitcherButton: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label(
                DataContextSwitcherLabels.title(for: currentContext, in: appEnvironment),
                systemImage: "person.crop.circle"
            )
        }
        .buttonStyle(.bordered)
        .fullScreenCover(isPresented: $showingPicker) {
            DataContextSwitcherPicker()
        }
    }

    private var currentContext: DataContext {
        appEnvironment?.accountsManager.currentContext ?? .local
    }
}
#endif
