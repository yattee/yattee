//
//  PeerTubeFiltersSheet.swift
//  Yattee
//
//  Sheet for filtering PeerTube instances in the explore view.
//

import SwiftUI

struct PeerTubeFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: PeerTubeDirectoryFilters
    let languages: [String]
    let countries: [String]
    let onApply: () -> Void

    var body: some View {
        #if os(macOS)
        // Popover content: filters apply live, click-outside dismisses.
        filtersForm
            .onChange(of: filters) { _, _ in onApply() }
            .padding()
            .frame(width: 300)
        #else
        NavigationStack {
            filtersForm
            #if os(tvOS)
            .scrollClipDisabled()
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
            .onChange(of: filters.language) { _, _ in onApply() }
            .onChange(of: filters.country) { _, _ in onApply() }
            #else
            .navigationTitle(String(localized: "peertube.explore.filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.apply")) {
                        onApply()
                        dismiss()
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        #endif
    }

    private var filtersForm: some View {
        Form {
            // Language filter
            if !languages.isEmpty {
                Section {
                    Picker(String(localized: "peertube.filter.language"), selection: $filters.language) {
                        Text(String(localized: "common.any")).tag(nil as String?)
                        ForEach(languages, id: \.self) { lang in
                            Text(languageDisplayName(lang)).tag(lang as String?)
                        }
                    }
                }
            }

            // Country filter
            if !countries.isEmpty {
                Section {
                    Picker(String(localized: "peertube.filter.country"), selection: $filters.country) {
                        Text(String(localized: "common.any")).tag(nil as String?)
                        ForEach(countries, id: \.self) { country in
                            Text(countryDisplayName(country)).tag(country as String?)
                        }
                    }
                }
            }

            // Reset button
            Section {
                Button(role: .destructive) {
                    filters = PeerTubeDirectoryFilters()
                } label: {
                    HStack {
                        Spacer()
                        Text(String(localized: "common.reset"))
                        Spacer()
                    }
                }
                .disabled(filters.isDefault)
            }
        }
    }

    private func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private func countryDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

// MARK: - Preview

#Preview {
    PeerTubeFiltersSheet(
        filters: .constant(PeerTubeDirectoryFilters()),
        languages: ["en", "fr", "de", "es", "ja"],
        countries: ["US", "FR", "DE", "ES", "JP"],
        onApply: {}
    )
}
