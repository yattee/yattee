//
//  BatchDownloadQualitySheet.swift
//  Yattee
//
//  Sheet for selecting download quality when batch downloading multiple videos.
//

import SwiftUI

#if !os(tvOS)
struct BatchDownloadQualitySheet: View {
    let videoCount: Int
    let onConfirm: (DownloadQuality, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var selectedQuality: DownloadQuality = .best
    @State private var includeSubtitles = false

    /// Quality options excluding "Ask" since we're already in the ask flow
    private var qualityOptions: [DownloadQuality] {
        DownloadQuality.allCases.filter { $0 != .ask }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "batchDownload.quality"), selection: $selectedQuality) {
                        ForEach(qualityOptions, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                } header: {
                    Text("batchDownload.subtitle \(videoCount)")
                }

                Section {
                    Toggle(String(localized: "batchDownload.includeSubtitles"), isOn: $includeSubtitles)
                }
            }
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(Color(.systemGroupedBackground))
            #endif
            .navigationTitle(String(localized: "batchDownload.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "batchDownload.start")) {
                        onConfirm(selectedQuality, includeSubtitles)
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Pre-select quality based on settings if available
                if let settingsManager = appEnvironment?.settingsManager {
                    // Use preferred video quality as a hint for download quality
                    if let maxRes = settingsManager.preferredQuality.maxResolution {
                        // Find matching download quality
                        for quality in qualityOptions {
                            if quality.maxResolution == maxRes {
                                selectedQuality = quality
                                break
                            }
                        }
                    }
                }

                // Pre-check subtitles if user has a preferred subtitle language
                if let preferredSubtitles = appEnvironment?.settingsManager.preferredSubtitlesLanguage,
                   !preferredSubtitles.isEmpty {
                    includeSubtitles = true
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    BatchDownloadQualitySheet(videoCount: 15) { _, _ in }
    .appEnvironment(.preview)
}
#endif
