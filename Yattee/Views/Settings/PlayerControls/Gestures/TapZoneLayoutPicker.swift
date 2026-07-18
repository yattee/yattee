//
//  TapZoneLayoutPicker.swift
//  Yattee
//
//  Visual picker for selecting tap zone layouts.
//

import SwiftUI

/// Visual grid picker for selecting a tap zone layout.
struct TapZoneLayoutPicker: View {
    @Binding var selectedLayout: TapZoneLayout

    private let layouts = TapZoneLayout.allCases
    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(layouts) { layout in
                LayoutOption(
                    layout: layout,
                    isSelected: selectedLayout == layout
                )
                .onTapGesture {
                    selectedLayout = layout
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Layout Option

private struct LayoutOption: View {
    let layout: TapZoneLayout
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                LayoutPreviewMiniature(layout: layout)
                    .padding(6)
            }
            .frame(width: 70, height: 50)

            Text(layout.layoutDescription)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Layout Preview Miniature

private struct LayoutPreviewMiniature: View {
    let layout: TapZoneLayout

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            switch layout {
            case .single:
                singleZone(size: size)
            case .horizontalSplit:
                horizontalSplit(size: size)
            case .verticalSplit:
                verticalSplit(size: size)
            case .threeColumns:
                threeColumns(size: size)
            case .quadrants:
                quadrants(size: size)
            }
        }
    }

    private func singleZone(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(0.4))
            .frame(width: size.width, height: size.height)
    }

    private func horizontalSplit(size: CGSize) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.4))
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.6))
        }
    }

    private func verticalSplit(size: CGSize) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.4))
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.6))
        }
    }

    private func threeColumns(size: CGSize) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.4))
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.5))
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.6))
        }
    }

    private func quadrants(size: CGSize) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.4))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.5))
            }
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.5))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.6))
            }
        }
    }
}

#Preview {
    Form {
        Section("Layout") {
            TapZoneLayoutPicker(selectedLayout: .constant(.horizontalSplit))
        }
    }
}
