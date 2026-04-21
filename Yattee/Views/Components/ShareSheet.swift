//
//  ShareSheet.swift
//  Yattee
//
//  Cross-platform share sheet for exporting content.
//

import SwiftUI

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
struct ShareSheet: View {
    let items: [Any]

    var body: some View {
        VStack(spacing: 12) {
            if let text = items.first as? String {
                ScrollView {
                    Text(text)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 400)
            }

            Button(String(localized: "settings.advanced.logs.export.copy")) {
                if let text = items.first as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}
#endif
