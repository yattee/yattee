//
//  View+NavigationSubtitle.swift
//  Yattee
//
//  Conditionally applies .navigationSubtitle on iOS 26+ and macOS 26+.
//

import SwiftUI

struct NavigationSubtitleModifier: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *), let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
        #elseif os(macOS)
        if #available(macOS 26, *), let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func navigationSubtitleIfAvailable(_ subtitle: String?) -> some View {
        modifier(NavigationSubtitleModifier(subtitle: subtitle))
    }
}
