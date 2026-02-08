//
//  ExpandableText.swift
//  Yattee
//
//  Text view that shows a limited number of lines with a "more" button to expand.
//

import SwiftUI

struct ExpandableText: View {
    let text: String
    var lineLimit: Int = 2
    @Binding var isExpanded: Bool

    @Environment(\.font) private var font

    @State private var fullHeight: CGFloat = 0
    @State private var truncatedHeight: CGFloat = 0

    private var isTruncated: Bool {
        fullHeight > truncatedHeight + 1 && truncatedHeight > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(isExpanded ? nil : lineLimit)
                .background(
                    // Measure truncated height
                    Text(text)
                        .font(font)
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            truncatedHeight = $0
                        }
                )
                .background(
                    // Measure full height
                    Text(text)
                        .font(font)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            fullHeight = $0
                        }
                )

            if isTruncated {
                Button {
                    toggle()
                } label: {
                    Text(isExpanded ? String(localized: "common.less") : String(localized: "common.more"))
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            if isTruncated {
                toggle()
            }
        }
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isExpanded.toggle()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ExpandableText(
            text: "Short text that fits in two lines.",
            lineLimit: 2,
            isExpanded: .constant(false)
        )
        .font(.caption)
        .padding()

        ExpandableText(
            text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
            lineLimit: 2,
            isExpanded: .constant(false)
        )
        .font(.caption)
        .padding()
    }
}
