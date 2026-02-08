//
//  VideoNavigationButton.swift
//  Yattee
//
//  Navigation button for switching between videos in VideoInfoView.
//

import SwiftUI

/// A floating circular button for navigating between videos in a queue.
/// Used in VideoInfoView to switch to previous/next video.
struct VideoNavigationButton: View {
    let direction: Direction
    let action: () -> Void
    var isLoading: Bool = false
    var hasError: Bool = false
    
    enum Direction {
        case previous
        case next
        
        var icon: String {
            switch self {
            case .previous: return "chevron.left"
            case .next: return "chevron.right"
            }
        }
        
        var accessibilityLabel: String {
            switch self {
            case .previous: return String(localized: "video.navigation.previous")
            case .next: return String(localized: "video.navigation.next")
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary)
                } else {
                    Image(systemName: direction.icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glassBackground(.regular, in: .circle)
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .overlay {
                if hasError {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(direction.accessibilityLabel)
    }
}

// MARK: - Preview

#Preview("Previous") {
    VideoNavigationButton(direction: .previous) {}
    .padding()
}

#Preview("Next") {
    VideoNavigationButton(direction: .next) {}
    .padding()
}
