//
//  TVSidebarDetailContainer.swift
//  Yattee
//
//  Decorates a tvOS detail screen with a fixed 400pt left sidebar showing
//  a large SF Symbol and a title, matching the look of tvOS settings.
//

#if os(tvOS)
import SwiftUI

struct TVSidebarDetailContainer<Content: View, BottomAction: View>: View {
    let content: Content
    let bottomAction: BottomAction
    var systemImage: String?
    var title: String?

    init(
        systemImage: String? = nil,
        title: String? = nil,
        @ViewBuilder bottomAction: () -> BottomAction = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.bottomAction = bottomAction()
        self.systemImage = systemImage
        self.title = title
    }

    var body: some View {
        content
            .focusSection()
            .safeAreaInset(edge: .leading) {
                if let systemImage {
                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 16) {
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
                        }
                        .allowsHitTesting(false)

                        if BottomAction.self != EmptyView.self {
                            bottomAction
                                .padding(.top, 40)
                                .focusSection()
                        }

                        Spacer()
                    }
                    .frame(width: 400)
                } else {
                    Spacer()
                        .frame(width: 400)
                        .allowsHitTesting(false)
                }
            }
    }
}
#endif
