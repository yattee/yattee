//
//  BookmarkTagsView.swift
//  Yattee
//
//  Read-only tag display for bookmark list/grid views.
//

import SwiftUI

/// Read-only display of bookmark tags with optional overflow indicator.
struct BookmarkTagsView: View {
    let tags: [String]
    var maxVisible: Int = 3
    
    @Environment(\.appEnvironment) private var appEnvironment
    
    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }
    
    private var visibleTags: [String] {
        Array(tags.prefix(maxVisible))
    }
    
    private var overflowCount: Int {
        max(0, tags.count - maxVisible)
    }
    
    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(visibleTags, id: \.self) { tag in
                    BookmarkTagChip(tag: tag, accentColor: accentColor)
                }
                
                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(accentColor)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Tag Chip (Read-Only)

/// Compact read-only tag chip for bookmark display.
struct BookmarkTagChip: View {
    let tag: String
    let accentColor: Color
    
    var body: some View {
        Text(tag)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accentColor.opacity(0.15))
            .foregroundStyle(accentColor)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Tags") {
    VStack(alignment: .leading, spacing: 16) {
        Text("3 tags (max 3):")
        BookmarkTagsView(tags: ["Swift", "iOS", "Tutorial"], maxVisible: 3)
        
        Text("5 tags (max 3):")
        BookmarkTagsView(tags: ["Swift", "iOS", "Tutorial", "SwiftUI", "Xcode"], maxVisible: 3)
        
        Text("5 tags (max 2):")
        BookmarkTagsView(tags: ["Swift", "iOS", "Tutorial", "SwiftUI", "Xcode"], maxVisible: 2)
        
        Text("Empty:")
        BookmarkTagsView(tags: [], maxVisible: 3)
    }
    .padding()
    .appEnvironment(.preview)
}
