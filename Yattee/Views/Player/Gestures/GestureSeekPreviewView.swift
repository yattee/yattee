//
//  GestureSeekPreviewView.swift
//  Yattee
//
//  Seek preview overlay shown during drag-to-seek gesture.
//

#if os(iOS)
import SwiftUI

/// Preview overlay shown during drag-to-seek gesture.
/// Shows only the storyboard thumbnail with timestamp overlay.
struct GestureSeekPreviewView: View {
    let storyboard: Storyboard?
    let currentTime: TimeInterval
    let seekTime: TimeInterval
    let duration: TimeInterval
    let storyboardService: StoryboardService
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme
    let chapters: [VideoChapter]
    let isActive: Bool

    @State private var opacity: Double = 0

    var body: some View {
        Group {
            // Only show if storyboard is available
            if let storyboard {
                SeekPreviewView(
                    storyboard: storyboard,
                    seekTime: seekTime,
                    storyboardService: storyboardService,
                    buttonBackground: buttonBackground,
                    theme: theme,
                    chapters: chapters
                )
            }
        }
        .opacity(opacity)
        .onChange(of: isActive) { _, active in
            withAnimation(.easeInOut(duration: 0.2)) {
                opacity = active ? 1 : 0
            }
        }
        .onAppear {
            if isActive {
                withAnimation(.easeOut(duration: 0.15)) {
                    opacity = 1
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black

        GestureSeekPreviewView(
            storyboard: nil,
            currentTime: 120,
            seekTime: 180,
            duration: 600,
            storyboardService: StoryboardService(),
            buttonBackground: .regularGlass,
            theme: .dark,
            chapters: [],
            isActive: true
        )
    }
}
#endif
