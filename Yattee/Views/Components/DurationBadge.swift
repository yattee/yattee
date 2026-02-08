//
//  DurationBadge.swift
//  Yattee
//
//  Reusable duration/time badge for video thumbnails.
//

import SwiftUI

/// A badge displaying duration or time remaining on video thumbnails.
struct DurationBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .fontWeight(.medium)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.75))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
