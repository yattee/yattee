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
    case failure(String)
}

// MARK: - Test Result Section

/// Displays the result of a connection test.
struct SourceTestResultSection: View {
    let result: SourceTestResult

    var body: some View {
        Section {
            switch result {
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
