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

    #if os(tvOS)
    private var content: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .padding(.vertical, 8)
                }
                Section {
                    Button { respond(true) } label: {
                        Label(confirmation.confirmTitle, systemImage: confirmation.systemImage)
                    }
                    Button(role: .cancel) { respond(false) } label: {
                        Label(String(localized: "common.cancel"), systemImage: "xmark")
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
        }
    }
    #else
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
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
    }
    #endif

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
