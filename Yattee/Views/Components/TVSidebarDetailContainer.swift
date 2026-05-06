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
    var showsDismissButton: Bool

    @Environment(\.dismiss) private var dismiss

    init(
        systemImage: String? = nil,
        title: String? = nil,
        showsDismissButton: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.systemImage = systemImage
        self.title = title
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        content
            .focusSection()
            .safeAreaInset(edge: .leading) {
                if let systemImage {
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
                    .frame(width: 400)
                } else {
                    Spacer()
                        .frame(width: 400)
                        .allowsHitTesting(false)
                }
            }
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Label(String(localized: "common.done"), systemImage: "chevron.backward")
                        }
                    }
                }
            }
    }
}
#endif
