//
//  DownloadProgressIndicator.swift
//  Yattee
//
//  Circular progress indicator for downloads.
//

import SwiftUI

/// Circular progress indicator showing download progress.
struct DownloadProgressIndicator: View {
    let progress: Double
    var size: CGFloat = 28
    /// When true, shows a spinner instead of progress arc (for unknown file sizes)
    var isIndeterminate: Bool = false

    private var strokeWidth: CGFloat {
        size > 24 ? 2 : 2
    }

    private var innerSize: CGFloat {
        size * 0.71  // Ratio from original (20/28 ≈ 0.71)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.6))
                .frame(width: size, height: size)

            if isIndeterminate {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(size / 32)
            } else {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: strokeWidth)
                    .frame(width: innerSize, height: innerSize)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .frame(width: innerSize, height: innerSize)
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        DownloadProgressIndicator(progress: 0.3, size: 22)
        DownloadProgressIndicator(progress: 0.5, size: 28)
        DownloadProgressIndicator(progress: 0.75, size: 28)
        DownloadProgressIndicator(progress: 0, size: 28, isIndeterminate: true)
    }
    .padding()
    .background(.gray)
}
