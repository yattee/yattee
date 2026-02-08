//
//  SwipeActionModifier.swift
//  Yattee
//
//  ViewModifier implementing swipe-to-reveal action buttons.
//

import SwiftUI

#if os(tvOS)

extension View {
    /// On tvOS, swipe actions are not supported - returns the view unmodified.
    @ViewBuilder
    func swipeActions(
        config: SwipeActionConfig = .init(),
        @SwipeActionBuilder actions: () -> [SwipeAction]
    ) -> some View {
        self
    }
}

#else

extension View {
    /// Adds swipe actions to a view (trailing swipe to reveal action buttons).
    @ViewBuilder
    func swipeActions(
        config: SwipeActionConfig = .init(),
        @SwipeActionBuilder actions: () -> [SwipeAction]
    ) -> some View {
        modifier(SwipeActionModifier(config: config, actions: actions()))
    }

    /// Adds swipe actions to a view using an array directly.
    /// Use this variant when building actions dynamically.
    @ViewBuilder
    func swipeActions(
        config: SwipeActionConfig = .init(),
        actionsArray: [SwipeAction]
    ) -> some View {
        modifier(SwipeActionModifier(config: config, actions: actionsArray))
    }
}

/// Shared state ensuring only one row can be swiped open at a time.
@MainActor
@Observable
final class SwipeActionSharedState {
    static let shared = SwipeActionSharedState()

    /// The ID of the currently active (swiped open) row, if any.
    var activeSwipeAction: String?

    private init() {}
}

/// ViewModifier that implements the swipe behavior with action buttons.
struct SwipeActionModifier: ViewModifier {
    var config: SwipeActionConfig
    var actions: [SwipeAction]

    // View state
    @State private var resetPositionTrigger = false
    @State private var offsetX: CGFloat = 0
    @State private var lastStoredOffsetX: CGFloat = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var progress: CGFloat = 0

    // Scroll tracking for auto-close on scroll
    @State private var currentScrollOffset: CGFloat = 0
    @State private var storedScrollOffset: CGFloat?

    // Shared state reference (computed to avoid inclusion in memberwise init)
    private var sharedState: SwipeActionSharedState { SwipeActionSharedState.shared }
    @State private var currentID = UUID().uuidString

    // iOS 17 fallback gesture state
    @GestureState private var isActive = false

    func body(content: Content) -> some View {
        Group {
            #if os(iOS)
            if #available(iOS 18, *) {
                swipeableContent(content)
                    .gesture(
                        SwipeGesture(
                            onBegan: { gestureDidBegan() },
                            onChange: { value in gestureDidChange(translation: value.translation) },
                            onEnded: { value in gestureDidEnded(translation: value.translation, velocity: value.velocity) }
                        )
                    )
            } else {
                fallbackSwipeableContent(content)
            }
            #else
            fallbackSwipeableContent(content)
            #endif
        }
        .onChange(of: resetPositionTrigger) { _, _ in
            reset()
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .scrollView).minY
        } action: { newValue in
            if let storedScrollOffset, storedScrollOffset != newValue {
                reset()
            }
        }
        .onChange(of: sharedState.activeSwipeAction) { _, newValue in
            if newValue != currentID && offsetX != 0 {
                reset()
            }
        }
    }

    /// Fallback using DragGesture for iOS 17 and macOS.
    @ViewBuilder
    private func fallbackSwipeableContent(_ content: Content) -> some View {
        swipeableContent(content)
            .gesture(
                DragGesture()
                    .updating($isActive) { _, out, _ in
                        out = true
                    }
                    .onChanged { value in
                        gestureDidChange(translation: value.translation)
                    }
                    .onEnded { value in
                        gestureDidEnded(
                            translation: value.translation,
                            velocity: CGSize(width: value.velocity.width, height: value.velocity.height)
                        )
                    }
            )
            .onChange(of: isActive) { oldValue, newValue in
                if newValue {
                    gestureDidBegan()
                }
            }
    }

    /// The content view with swipe overlay and offset applied.
    @ViewBuilder
    private func swipeableContent(_ content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .foregroundStyle(.clear)
                    .containerRelativeFrame(config.occupiesFullWidth ? .horizontal : .init())
                    .overlay(alignment: .trailing) {
                        actionsView
                    }
            }
            .compositingGroup()
            .offset(x: offsetX)
            .offset(x: bounceOffset)
            .mask {
                Rectangle()
                    .containerRelativeFrame(config.occupiesFullWidth ? .horizontal : .init())
            }
    }

    /// The action buttons that slide in from the trailing edge.
    @ViewBuilder
    private var actionsView: some View {
        ZStack {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]

                GeometryReader { proxy in
                    let size = proxy.size
                    let spacing = config.spacing * CGFloat(index)
                    let offset = (CGFloat(index) * size.width) + spacing

                    Button {
                        action.action { [self] in
                            resetPositionTrigger.toggle()
                        }
                    } label: {
                        Image(systemName: action.symbolImage)
                            .font(action.font)
                            .foregroundStyle(action.tint)
                            .frame(width: size.width, height: size.height)
                            .background(action.background, in: Circle())
                    }
                    .offset(x: offset * progress)
                }
                .frame(width: action.size.width, height: action.size.height)
            }
        }
        .visualEffect { content, proxy in
            content.offset(x: proxy.size.width)
        }
        .offset(x: config.leadingPadding)
        .opacity(progress == 0 ? 0 : 1)
    }

    // MARK: - Gesture Handlers

    private func gestureDidBegan() {
        storedScrollOffset = lastStoredOffsetX
        sharedState.activeSwipeAction = currentID
    }

    private func gestureDidChange(translation: CGSize) {
        offsetX = min(max(translation.width + lastStoredOffsetX, -maxOffsetWidth), 0)
        progress = -offsetX / maxOffsetWidth
        bounceOffset = min(translation.width - (offsetX - lastStoredOffsetX), 0) / 10
    }

    private func gestureDidEnded(translation: CGSize, velocity: CGSize) {
        let endTarget = velocity.width + offsetX

        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            if -endTarget > (maxOffsetWidth * 0.6) {
                // Snap open
                offsetX = -maxOffsetWidth
                bounceOffset = 0
                progress = 1
            } else {
                // Reset to closed
                reset()
            }
        }

        lastStoredOffsetX = offsetX
    }

    private func reset() {
        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            offsetX = 0
            lastStoredOffsetX = 0
            progress = 0
            bounceOffset = 0
        }

        storedScrollOffset = nil
    }

    /// Maximum offset width based on action sizes and spacing.
    private var maxOffsetWidth: CGFloat {
        let totalActionSize = actions.reduce(CGFloat.zero) { result, action in
            result + action.size.width
        }

        let spacing = config.spacing * CGFloat(actions.count - 1)
        return totalActionSize + spacing + config.leadingPadding + config.trailingPadding
    }
}

#endif
