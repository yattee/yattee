//
//  SubtitleFilePicker.swift
//  Yattee
//
//  File pickers for loading an external subtitle file into the current playback.
//  iOS uses a document picker sheet, macOS an NSOpenPanel. Not available on tvOS.
//

import SwiftUI
import UniformTypeIdentifiers

#if !os(tvOS)

/// Content types accepted by the subtitle file pickers.
enum SubtitleFileTypes {
    /// Dynamic UTTypes for the supported subtitle extensions (srt/vtt/ass/ssa/sub —
    /// none of them have built-in UTType constants).
    static var contentTypes: [UTType] {
        let types = MediaFile.subtitleExtensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.data] : types
    }
}

#if os(iOS)
struct SubtitleFilePickerView: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: SubtitleFileTypes.contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
    }
}
#endif

#if os(macOS)
enum SubtitleFilePanel {
    @MainActor
    static func present(onSelect: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SubtitleFileTypes.contentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "stream.subtitles.loadFromFile.message")

        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}
#endif

#endif
