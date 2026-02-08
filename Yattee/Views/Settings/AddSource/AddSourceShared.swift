//
//  AddSourceShared.swift
//  Yattee
//
//  Shared components for the Add Source views.
//

import SwiftUI

// MARK: - Test Result

/// Result of a connection test for WebDAV/SMB sources.
enum SourceTestResult {
    case success
    case successWithBandwidth(BandwidthTestResult)
    case failure(String)
}

// MARK: - Test Result Section

/// Displays the result of a connection test.
struct SourceTestResultSection: View {
    let result: SourceTestResult

    var body: some View {
        Section {
            switch result {
            case .success:
                Label(String(localized: "sources.status.connected"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .successWithBandwidth(let bandwidth):
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "sources.status.connected"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if bandwidth.hasWriteAccess {
                        if let upload = bandwidth.formattedUploadSpeed {
                            Label(String(localized: "sources.bandwidth.upload \(upload)"), systemImage: "arrow.up.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let download = bandwidth.formattedDownloadSpeed {
                        Label(String(localized: "sources.bandwidth.download \(download)"), systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !bandwidth.hasWriteAccess {
                        Label(String(localized: "sources.status.readOnly"), systemImage: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    if let warning = bandwidth.warning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            case .failure(let error):
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Folder Picker (iOS)

#if os(iOS)
import UniformTypeIdentifiers

struct FolderPickerView: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            onSelect(url)
        }
    }
}
#endif
