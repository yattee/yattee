//
//  CompactPreviewButtonView.swift
//  Yattee
//
//  Simplified button preview for pill and mini player editors.
//  Renders icon buttons without complex features like sliders, title/author, or spacers.
//

import SwiftUI

struct CompactPreviewButtonView: View {
    let configuration: ControlButtonConfiguration
    let size: CGFloat

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: iconSize))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: size)
    }

    // MARK: - Private

    /// Icon name, using seek settings for seek buttons
    private var iconName: String {
        if configuration.buttonType == .seek, let seekSettings = configuration.seekSettings {
            return seekSettings.systemImage
        }
        return configuration.buttonType.systemImage
    }

    /// Play/pause is slightly larger than other buttons
    private var iconSize: CGFloat {
        configuration.buttonType == .playPause ? size * 0.9 : size * 0.7
    }
}
