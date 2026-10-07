//
//  LinkActionConfirmationSheet.swift
//  Yattee
//
//  Asks before a URL scheme action changes saved state. Any web page can open
//  a yattee:// link, so queueing, bookmarking, downloading and subscribing
//  wait for the user unless Settings allows them to run on their own.
//

import SwiftUI

/// A pending question for `LinkActionConfirmationSheet`. Answered exactly once:
/// by a button, or as "cancel" when the sheet goes away any other way.
@MainActor
final class LinkActionConfirmation {
    let id = UUID()
    let title: String
    let subject: String?
    let detail: String?
    let confirmTitle: String
    let systemImage: String

    private var continuation: CheckedContinuation<Bool, Never>?

    init(title: String, subject: String?, detail: String?, confirmTitle: String, systemImage: String) {
        self.title = title
        self.subject = subject
        self.detail = detail
        self.confirmTitle = confirmTitle
        self.systemImage = systemImage
    }

    /// Presents the sheet through the top-most host and waits for the answer.
    func ask(using presenter: PresentationRouter) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            presenter.present(.linkActionConfirmation(self))
        }
    }

    func answer(_ allowed: Bool) {
        continuation?.resume(returning: allowed)
        continuation = nil
    }
}

extension LinkActionConfirmation: Equatable {
    nonisolated static func == (lhs: LinkActionConfirmation, rhs: LinkActionConfirmation) -> Bool {
        lhs === rhs
    }
}

struct LinkActionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let confirmation: LinkActionConfirmation

    var body: some View {
        content
            .onDisappear {
                // Swiped away or replaced by another sheet: treat as cancel
                confirmation.answer(false)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            HStack(spacing: 12) {
                Button(role: .cancel) { respond(false) } label: {
                    Text(String(localized: "common.cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { respond(true) } label: {
                    Label(confirmation.confirmTitle, systemImage: confirmation.systemImage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(20)

            Spacer(minLength: 0)
        }
        #if os(macOS)
        .frame(width: 380)
        #endif
        #if !os(tvOS)
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(confirmation.title)
                .font(.headline)
            if let subject = confirmation.subject {
                Text(subject)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if let detail = confirmation.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func respond(_ allowed: Bool) {
        confirmation.answer(allowed)
        dismiss()
    }
}

#if os(tvOS)
extension View {
    /// Presents a link action confirmation as an alert. tvOS sheets fill most
    /// of the screen, too much for a two-button question.
    func linkActionConfirmationAlert(
        _ confirmation: LinkActionConfirmation?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        alert(
            confirmation?.title ?? "",
            isPresented: Binding {
                confirmation != nil
            } set: { isPresented in
                if !isPresented { onDismiss() }
            },
            presenting: confirmation
        ) { confirmation in
            Button(confirmation.confirmTitle) { confirmation.answer(true) }
            Button(String(localized: "common.cancel"), role: .cancel) { confirmation.answer(false) }
        } message: { confirmation in
            Text([confirmation.subject, confirmation.detail].compactMap { $0 }.joined(separator: "\n"))
        }
        .onChange(of: confirmation) { previous, _ in
            // Gone without an answer (Menu button, external navigation, another
            // sheet): treat as cancel. Deferred so a button's answer comes first.
            guard let previous else { return }
            Task { @MainActor in previous.answer(false) }
        }
    }
}
#endif
