//
//  AccountRenameAlert.swift
//  Yattee
//
//  The one place an account's synced label is set.
//

import SwiftUI

/// An account the user asked to rename, and what its field starts on.
///
/// Carries the strings rather than the account so the surfaces that name an
/// account differently — an orphan resolves through no source — can each say
/// what the field should offer, while the alert itself stays the same
/// everywhere.
struct AccountRenameRequest: Identifiable {
    let id: UUID

    /// The label the account shows with no user-set name. Doubles as the
    /// placeholder and as the value that means "no custom name at all".
    let defaultName: String

    /// What the field is prefilled with: the label the row is showing now.
    let initialText: String

    /// Whether that prefill is a name the user chose, as opposed to the label
    /// the account falls back to on this device. It is what tells an untouched
    /// save to keep the name from one that must not publish a device-local
    /// fallback — see `DataContextValidator.renamedDisplayName`.
    let hasUserSetLabel: Bool
}

extension AccountRenameRequest {
    /// The request for an account that still resolves through a source.
    ///
    /// The single place the alert's strings are derived, so both surfaces that
    /// offer Rename ask the validator the same two questions: what the row is
    /// showing, and what clearing the field goes back to.
    @MainActor
    static func forAccount(_ account: Account, resolvedBy validator: DataContextValidator) -> Self {
        Self(
            id: account.id,
            defaultName: validator.defaultDisplayName(for: account),
            initialText: validator.displayName(for: account),
            hasUserSetLabel: account.hasUserSetDisplayName
        )
    }

    /// The request for an account with no source to resolve through.
    ///
    /// The fallback is the caller's to name: the validator's last resort for an
    /// account whose instance is gone is the words "Source missing", which is a
    /// diagnosis and not a name to offer the field.
    static func forAccount(_ account: Account, fallingBackTo defaultName: String) -> Self {
        Self(
            id: account.id,
            defaultName: defaultName,
            initialText: account.displayName ?? "",
            hasUserSetLabel: account.hasUserSetDisplayName
        )
    }
}

extension Account {
    /// Whether the account carries a label the user chose. An empty string is
    /// no more a name than `nil` is, and both arrive here from old records.
    var hasUserSetDisplayName: Bool {
        !(displayName ?? "").isEmpty
    }
}

/// The rename alert, shared by every screen that lists accounts.
///
/// A text field in an alert rather than a sheet: the whole edit is one short
/// string, and it is the app's existing way of asking for one on tvOS, where
/// there is no sheet-sized form for a single field.
private struct AccountRenameAlertModifier: ViewModifier {
    @Binding var request: AccountRenameRequest?
    let onCommit: (UUID, String?) -> Void

    @State private var text = ""

    func body(content: Content) -> some View {
        content
            // Keyed on the ID rather than on the request: the prefill has to be
            // in place before the alert's field is built, and re-entering the
            // same row is the only time the text should be reset.
            //
            // Seeded only when a request appears, never blanked when one goes
            // away. Dismissal sets the request to nil while the alert's buttons
            // are still live, and Save reads this text when it runs — blanking
            // here would let the two race, with an emptied field committing as
            // "clear the name".
            .onChange(of: request?.id) { _, _ in
                if let request { text = request.initialText }
            }
            .alert(
                String(localized: "accounts.rename.title"),
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                presenting: request
            ) { pending in
                TextField(pending.defaultName, text: $text)

                Button(String(localized: "common.save")) {
                    onCommit(
                        pending.id,
                        DataContextValidator.renamedDisplayName(
                            text,
                            prefilledWith: pending.initialText,
                            hasUserSetLabel: pending.hasUserSetLabel
                        )
                    )
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: { pending in
                Text(String(localized: "accounts.rename.message \(pending.defaultName)"))
            }
    }
}

extension View {
    /// Presents the rename alert for `request`, calling `onCommit` with the
    /// label to store — `nil` when the user cleared it.
    func accountRenameAlert(
        _ request: Binding<AccountRenameRequest?>,
        onCommit: @escaping (UUID, String?) -> Void
    ) -> some View {
        modifier(AccountRenameAlertModifier(request: request, onCommit: onCommit))
    }
}
