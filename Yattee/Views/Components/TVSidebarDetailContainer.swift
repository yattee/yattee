//
//  TVSidebarDetailContainer.swift
//  Yattee
//
//  Decorates a tvOS detail screen with a fixed 400pt left sidebar showing
//  a large SF Symbol and a title, matching the look of tvOS settings.
//

#if os(tvOS)
import SwiftUI

struct TVSidebarDetailContainer<Content: View>: View {
    let content: Content
    var systemImage: String?
    var title: String?

    init(systemImage: String? = nil, title: String? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.systemImage = systemImage
        self.title = title
    }

    var body: some View {
        content
            .safeAreaInset(edge: .leading) {
                if let systemImage {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: systemImage)
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                        if let title {
                            Text(title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .frame(width: 400)
                    .allowsHitTesting(false)
                } else {
                    Spacer()
                        .frame(width: 400)
                        .allowsHitTesting(false)
                }
            }
    }
}
#endif
