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
            .onChange(of: request?.id) { _, _ in
                text = request?.initialText ?? ""
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
                        DataContextValidator.renamedDisplayName(text, fallingBackTo: pending.defaultName)
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
