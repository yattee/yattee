//
//  TagInputView.swift
//  Yattee
//
//  Reusable tag input component with chip-style display.
//

import SwiftUI

struct TagInputView: View {
    @Binding var tags: [String]
    var isFocused: Bool = false

    @Environment(\.appEnvironment) private var appEnvironment

    @State private var inputText: String = ""
    @State private var showMaxTagsWarning = false
    @State private var showMaxLengthWarning = false
    @FocusState private var textFieldFocused: Bool
    
    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }
    
    private let maxTags = 10
    private let maxTagLength = 30
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag chips display
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(
                            tag: tag,
                            accentColor: accentColor,
                            onRemove: {
                                removeTag(tag)
                            }
                        )
                    }
                }
            }
            
            // Input field
            HStack {
                TextField(String(localized: "bookmark.tags.placeholder"), text: $inputText)
                    .focused($textFieldFocused)
                    #if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .onSubmit {
                        addTag()
                    }
                    .onChange(of: inputText) { _, newValue in
                        // Auto-add tag on comma
                        if newValue.contains(",") {
                            addTag()
                        }
                    }
                    .disabled(tags.count >= maxTags)
                    .onAppear {
                        if isFocused {
                            textFieldFocused = true
                        }
                    }
                
                if !inputText.isEmpty {
                    Button(String(localized: "bookmark.tags.add")) {
                        addTag()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .disabled(tags.count >= maxTags)
                }
            }
            
            // Warning messages
            if showMaxTagsWarning {
                Text(String(localized: "bookmark.tags.maxReached \(maxTags)"))
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if showMaxLengthWarning {
                Text(String(localized: "bookmark.tags.tooLong \(maxTagLength)"))
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if tags.count >= maxTags - 2 {
                Text(String(localized: "bookmark.tags.remaining \(maxTags - tags.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func addTag() {
        // Reset warnings
        showMaxTagsWarning = false
        showMaxLengthWarning = false
        
        // Extract text (handle comma-separated input)
        let tagText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate
        guard !tagText.isEmpty else {
            inputText = ""
            return
        }
        
        guard tags.count < maxTags else {
            showMaxTagsWarning = true
            inputText = ""
            return
        }
        
        guard tagText.count <= maxTagLength else {
            showMaxLengthWarning = true
            return
        }
        
        guard !tags.contains(tagText) else {
            // Duplicate - just clear input
            inputText = ""
            return
        }
        
        // Add tag
        tags.append(tagText)
        inputText = ""
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let accentColor: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(accentColor.opacity(0.8))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

/// Simple flow layout for wrapping tags horizontally
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowLayoutResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowLayoutResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowLayoutResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var tags = ["Swift", "iOS", "SwiftUI", "Tutorial"]
    
    Form {
        Section("Tags") {
            TagInputView(tags: $tags)
        }
    }
    .appEnvironment(.preview)
}
