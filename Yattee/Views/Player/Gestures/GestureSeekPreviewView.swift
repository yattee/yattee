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
    let seekTime: TimeInterval
    let duration: TimeInterval
    let storyboardService: StoryboardService
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme
    let chapters: [VideoChapter]
    let isActive: Bool
    var availableWidth: CGFloat = 320

    @State private var opacity: Double = 0

    private var currentChapter: VideoChapter? {
        chapters.last { $0.startTime <= seekTime }
    }

    var body: some View {
        VStack(spacing: 6) {
            if let chapter = currentChapter {
                ChapterCapsuleView(
                    title: chapter.title,
                    buttonBackground: buttonBackground
                )
                .frame(maxWidth: availableWidth - 16)
            }

            if let storyboard {
                SeekPreviewView(
                    storyboard: storyboard,
                    seekTime: seekTime,
                    storyboardService: storyboardService,
                    buttonBackground: buttonBackground,
                    theme: theme
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
