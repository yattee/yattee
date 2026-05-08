//
//  ToastCardView.swift
//  Yattee
//
//  Individual toast notification card component.
//

import SwiftUI

/// A single toast notification card.
struct ToastCardView: View {
    let toast: Toast
    let onDismiss: () -> Void
    let onAction: (() async -> Void)?
    var onDragBegan: (() -> Void)? = nil
    var onDragCancelled: (() -> Void)? = nil

    @State private var isAnimating = false
    #if os(iOS)
    @State private var dragOffset: CGFloat = 0
    @State private var didNotifyDragBegan = false
    #endif

    var body: some View {
        HStack(spacing: Self.iconSpacing) {
            // Leading icon or progress indicator
            leadingIcon

            // Title and optional subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Action button (if present)
            if let action = toast.action {
                actionButton(action)
            }

            // Dismiss button (macOS only - iOS uses swipe)
            #if os(macOS)
            dismissButton
            #endif
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: 400, alignment: .leading)
        .glassBackground(.regular, in: .capsule, fallback: .regularMaterial)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .scaleEffect(isAnimating ? 1 : 0.9)
        #if os(iOS)
        .compositingGroup()
        .opacity(Double(1 - min(abs(min(dragOffset, 0)) / 120, 1)))
        .offset(y: min(dragOffset, 0))
        .contentShape(Capsule())
        .simultaneousGesture(swipeGesture)
        #endif
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }

    #if os(iOS)
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !didNotifyDragBegan {
                    didNotifyDragBegan = true
                    onDragBegan?()
                }
                let h = value.translation.height
                let target: CGFloat = h < 0 ? h : h * 0.2
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    dragOffset = target
                }
            }
            .onEnded { value in
                didNotifyDragBegan = false
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if translation < -60 || predicted < -200 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = -200
                    }
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                    onDragCancelled?()
                }
            }
    }
    #endif

    @ViewBuilder
    private var leadingIcon: some View {
        // Use fixed frame to prevent size changes when switching between spinner and icon
        Group {
            // If icon is explicitly set, show it (used for success/error states after update)
            if let icon = toast.icon {
                Image(systemName: icon)
                    .foregroundStyle(toast.iconColor ?? .primary)
                    .font(.title3)
            } else if toast.category == .loading || toast.category == .remoteControl {
                // Show spinner for loading/remoteControl when no icon is set
                ProgressView()
                    .controlSize(.small)
                    #if os(iOS) || os(macOS)
                    .tint(.primary)
                    #endif
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
    }

    private static var iconSpacing: CGFloat {
        #if os(tvOS)
        20
        #else
        12
        #endif
    }

    private static var horizontalPadding: CGFloat {
        #if os(tvOS)
        20
        #else
        16
        #endif
    }

    private static var iconSize: CGFloat {
        #if os(tvOS)
        32
        #else
        22
        #endif
    }

    @ViewBuilder
    private func actionButton(_ action: ToastAction) -> some View {
        Button {
            Task {
                await onAction?()
            }
        } label: {
            HStack(spacing: 4) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                Text(action.label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
    #endif
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ToastCardView(
            toast: Toast(
                category: .loading,
                title: "Loading Video"
            ),
            onDismiss: {},
            onAction: nil
        )

        ToastCardView(
            toast: Toast(
                category: .success,
                title: "Download Completed",
                subtitle: "My Awesome Video Title",
                icon: "checkmark.circle.fill",
                iconColor: .green
            ),
            onDismiss: {},
            onAction: nil
        )

        ToastCardView(
            toast: Toast(
                category: .sponsorBlock,
                title: "Skipping Sponsor",
                subtitle: "30 seconds",
                icon: "forward.fill",
                iconColor: .green,
                action: ToastAction(
                    label: "Undo",
                    systemImage: "arrow.uturn.backward"
                ) {}
            ),
            onDismiss: {},
            onAction: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
