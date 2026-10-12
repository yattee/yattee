//
//  ExpandedPlayerWindow.swift
//  Yattee
//
//  Manages expanded player window on iOS.
//  Uses a separate UIWindow above main content for reliable presentation/dismissal.
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Status Bar Visibility Controller

/// Observable controller for status bar visibility
@Observable
final class StatusBarVisibilityController {
    var isHidden: Bool = false
    weak var viewController: UIViewController?
    /// Last non-zero status bar height seen — layouts that keep a fixed
    /// status-bar-sized inset while the bar is hidden (corner layout) read
    /// it because the safe area reports 0 once the bar is gone.
    var knownStatusBarHeight: CGFloat = 0

    func setHidden(_ hidden: Bool) {
        rememberStatusBarHeight(
            viewController?.view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        )
        isHidden = hidden
        viewController?.setNeedsStatusBarAppearanceUpdate()
    }

    func rememberStatusBarHeight(_ height: CGFloat) {
        if height > 0 { knownStatusBarHeight = height }
    }
}

/// Environment key for status bar controller
private struct StatusBarVisibilityControllerKey: EnvironmentKey {
    static var defaultValue: StatusBarVisibilityController? = nil
}

extension EnvironmentValues {
    var statusBarVisibilityController: StatusBarVisibilityController? {
        get { self[StatusBarVisibilityControllerKey.self] }
        set { self[StatusBarVisibilityControllerKey.self] = newValue }
    }
}

/// View modifier to hide status bar in ExpandedPlayerWindow
private struct StatusBarHiddenModifier: ViewModifier {
    let hidden: Bool
    @Environment(\.statusBarVisibilityController) private var controller

    func body(content: Content) -> some View {
        content
            .onChange(of: hidden, initial: true) { _, newValue in
                controller?.setHidden(newValue)
            }
    }
}

extension View {
    /// Hides the status bar when presented in ExpandedPlayerWindow
    func playerStatusBarHidden(_ hidden: Bool = true) -> some View {
        modifier(StatusBarHiddenModifier(hidden: hidden))
    }
}

/// View controller for expanded player that supports all orientations
private final class ExpandedPlayerHostingController<Content: View>: UIHostingController<Content> {
    /// Controller to communicate status bar visibility from SwiftUI
    let statusBarController: StatusBarVisibilityController
    
    /// Callback when rotation transition occurs (viewWillTransition is called)
    var onRotationTransition: (() -> Void)?

    init(rootView: Content, statusBarController: StatusBarVisibilityController) {
        self.statusBarController = statusBarController
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var prefersStatusBarHidden: Bool {
        statusBarController.isHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    /// The player is a video-first, mostly non-scrolling UI: keep the status bar horizontal
    /// (iPhone Duo exterior) instead of reserving a trailing column beside the video.
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        .disabled
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        // Notify window manager that rotation is occurring
        // This works for both system auto-rotate AND manual fullscreen toggle
        onRotationTransition?()

        // Update window frame to match new scene bounds after rotation or resize
        // Use coordinateSpace.bounds for proper iPad Stage Manager / Split View support
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let window = self?.view.window,
                  let scene = window.windowScene else { return }
            window.frame = scene.coordinateSpace.bounds
        }, completion: { [weak self] _ in
            // Folding/unfolding the iPhone Duo (and display handoffs in
            // general) changes the safe area without a rotation; SwiftUI
            // keeps serving the previous insets to the sheet's GeometryReader
            // until the hosting controller's safe area is invalidated. Nudge
            // additionalSafeAreaInsets, the same trick the dismiss path uses
            // for the main window.
            guard let self else { return }
            let originalInsets = self.additionalSafeAreaInsets
            self.additionalSafeAreaInsets = UIEdgeInsets(
                top: originalInsets.top + 1,
                left: originalInsets.left,
                bottom: originalInsets.bottom,
                right: originalInsets.right
            )
            self.additionalSafeAreaInsets = originalInsets
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure window size stays in sync with scene bounds during iPad resize
        // This handles Stage Manager / Split View live resize where viewWillTransition may not be called
        // Only update SIZE, not origin - origin is managed by drag-to-dismiss gesture
        guard let window = view.window,
              let scene = window.windowScene else { return }
        let sceneSize = scene.coordinateSpace.bounds.size
        if window.frame.size != sceneSize {
            window.frame.size = sceneSize
        }
    }
}

/// Handles drag-to-dismiss by tracking scroll view overscroll
private final class DragToDismissGestureHandler: NSObject, UIGestureRecognizerDelegate {
    weak var window: UIWindow?
    var onDismiss: (() -> Void)?
    var onDismissGestureStateChanged: ((Bool) -> Void)?
    var onHapticFeedback: (() -> Void)?

    // Panscan callbacks
    var onPanscanChanged: ((Double) -> Void)?
    var onPinchGestureStateChanged: ((Bool) -> Void)?
    var getCurrentPanscan: (() -> Double)?
    /// Returns true if panscan should snap to fit/fill when released
    var shouldSnapPanscan: (() -> Bool)?
    /// Returns true if panel is both pinned AND visible on screen
    var isPanelPinnedAndVisible: (() -> Bool)?
    /// Returns true if expanded comments view is showing (blocks sheet dismiss)
    var isCommentsExpanded: (() -> Bool)?
    /// Returns true if user is adjusting volume/brightness sliders (blocks sheet dismiss)
    var isAdjustingPlayerSliders: (() -> Bool)?
    /// Returns true if user is dragging the portrait panel (blocks sheet dismiss)
    var isPanelDragging: (() -> Bool)?
    /// Returns the portrait panel frame in screen coordinates (for gesture conflict resolution)
    var getPortraitPanelFrame: (() -> CGRect)?
    /// Returns the corner layout below-video panel frame in screen coordinates (blocks dismiss pan)
    var getCornerBelowPanelFrame: (() -> CGRect)?
    /// Returns the panel resize grabber strip frame in screen coordinates (blocks dismiss pan)
    var getPanelResizeGrabberFrame: (() -> CGRect)?
    var getPlayerSideSliderFrames: (() -> [CGRect])?
    /// Returns whether the portrait panel is currently visible (not hidden off-screen)
    var isPortraitPanelVisible: (() -> Bool)?
    /// Returns the progress bar frame in screen coordinates (for gesture conflict resolution)
    var getProgressBarFrame: (() -> CGRect)?
    /// Returns true if a seek gesture is currently active (blocks pinch gesture)
    var isSeekGestureActive: (() -> Bool)?
    /// Returns the comments overlay frame in screen coordinates (for gesture conflict resolution)
    var getCommentsFrame: (() -> CGRect)?

    // Main window scaling callbacks (Apple Music-style effect)
    var onMainWindowScaleChanged: ((CGFloat) -> Void)?
    var onMainWindowScaleAnimated: ((CGFloat) -> Void)?  // Animated scale to progress

    private let dismissThreshold: CGFloat = 100
    private var isDismissing = false
    private var scrollViewAtTop = false
    private weak var trackedScrollView: UIScrollView?
    private var scrollObservation: NSKeyValueObservation?

    // Panscan gesture state
    private var basePanscan: Double = 0.0

    func trackScrollView(_ scrollView: UIScrollView) {
        trackedScrollView = scrollView
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            self?.scrollViewAtTop = scrollView.contentOffset.y <= 0
        }
        scrollViewAtTop = scrollView.contentOffset.y <= 0
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = window else { return }

        let translation = gesture.translation(in: window)
        let velocity = gesture.velocity(in: window)

        switch gesture.state {
        case .began:
            isDismissing = false

        case .changed:
            // If user added a second finger (pinch), cancel the pan gesture entirely
            // so the SwiftUI MagnificationGesture can take over
            if gesture.numberOfTouches >= 2 {
                if isDismissing {
                    isDismissing = false
                    onDismissGestureStateChanged?(false)
                    UIView.animate(withDuration: 0.2) {
                        window.frame.origin.y = 0
                        // Restore main window scale when canceling drag
                        self.onMainWindowScaleChanged?(1.0)
                    }
                }
                // Cancel gesture by toggling enabled state - this releases the touches
                gesture.isEnabled = false
                gesture.isEnabled = true
                return
            }

            // Only start dismissing if scroll view is at top (or no scroll view) and pulling down
            let canDismiss = trackedScrollView == nil || scrollViewAtTop
            if canDismiss && translation.y > 0 {
                if !isDismissing {
                    isDismissing = true
                    onDismissGestureStateChanged?(true)
                }
                // Disable scroll view bouncing while dismissing
                trackedScrollView?.bounces = false
                // Move the window down with resistance
                window.frame.origin.y = translation.y * 0.5

                // Update main window scale based on drag progress
                // As user drags down, main window scales back towards normal (1.0 -> 0.0 progress)
                let dragProgress = min(translation.y / window.bounds.height, 1.0)
                let scaleProgress = 1.0 - dragProgress  // Invert: dragging down = scale back to normal
                onMainWindowScaleChanged?(scaleProgress)
            }

        case .ended, .cancelled:
            // Re-enable bouncing
            trackedScrollView?.bounces = true

            if isDismissing {
                let shouldDismiss = translation.y > dismissThreshold || velocity.y > 800

                if shouldDismiss {
                    // Trigger haptic immediately on release
                    onHapticFeedback?()

                    // The window manager owns the dismiss animation (morph into
                    // the mini player, or slide off screen) from the current position
                    onDismiss?()
                } else {
                    // Snap back - restore main window scale to fully scaled
                    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                        window.frame.origin.y = 0
                    } completion: { [weak self] _ in
                        // Delay dismiss gesture state change until after snap-back animation completes
                        // This keeps the black overlay hidden so user can see the scale animation
                        self?.onDismissGestureStateChanged?(false)
                    }
                    onMainWindowScaleAnimated?(1.0)
                }
            }
            isDismissing = false

        default:
            break
        }
    }

    /// Pinch gesture handler - updates panscan value based on gesture scale
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Capture current panscan when gesture starts
            basePanscan = getCurrentPanscan?() ?? 0.0
            onPinchGestureStateChanged?(true)

        case .changed:
            // Calculate delta from gesture scale (1.0 = no change)
            let rawDelta = (gesture.scale - 1.0) * 2.0

            // Apply ease-out curve for bouncy feel
            let easedDelta = rawDelta >= 0
                ? pow(rawDelta, 0.6)
                : -pow(-rawDelta, 0.6)

            // Calculate new panscan value, clamped to 0-1
            let newPanscan = max(0, min(1, basePanscan + easedDelta))
            onPanscanChanged?(newPanscan)

        case .ended, .cancelled:
            let currentPanscan = getCurrentPanscan?() ?? 0.0

            // Check if we should snap to fit/fill or allow free zoom
            if shouldSnapPanscan?() ?? true {
                // Snap to 0 or 1
                let targetPanscan: Double = currentPanscan > 0.5 ? 1.0 : 0.0
                animatePanscan(from: currentPanscan, to: targetPanscan)
            }
            // If not snapping, leave the value exactly where it is

            onPinchGestureStateChanged?(false)

        default:
            break
        }
    }

    /// Animates panscan value from start to end with ease-out curve
    private func animatePanscan(from start: Double, to end: Double) {
        let duration: Double = 0.25
        let steps = 15
        let stepDuration = duration / Double(steps)

        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            // Ease-out curve for smooth deceleration
            let easedProgress = 1 - pow(1 - progress, 3)
            let value = start + (end - start) * easedProgress

            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) { [weak self] in
                self?.onPanscanChanged?(value)
            }
        }
    }

    // Always begin - we'll check scroll position in handlePan
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow pinch gesture when pinned panel is visible on screen or seek gesture is active
        if gestureRecognizer is UIPinchGestureRecognizer {
            if isSeekGestureActive?() == true { return false }
            if isPortraitPanelVisible?() == true { return false }
            return !(isPanelPinnedAndVisible?() ?? false)
        }

        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }

        // Don't begin if this looks like a pinch gesture (2+ fingers)
        if panGesture.numberOfTouches >= 2 {
            return false
        }

        // Don't begin dismiss gesture if a sheet/modal is presented on top
        if let rootVC = window?.rootViewController,
           rootVC.presentedViewController != nil {
            return false
        }

        // When comments are expanded, only block dismiss if touch is within comments frame
        if isCommentsExpanded?() == true {
            let commentsFrame = getCommentsFrame?() ?? .zero
            if !commentsFrame.isEmpty {
                let touchLocation = panGesture.location(in: nil)
                if commentsFrame.contains(touchLocation) {
                    return false
                }
            } else {
                return false // No frame info — fall back to blanket blocking
            }
        }

        // Don't begin dismiss gesture when adjusting volume/brightness sliders
        if isAdjustingPlayerSliders?() == true {
            return false
        }

        // ...or when the touch starts on a slider: the flag above is set by
        // SwiftUI's DragGesture, which fires after this pan recognizes
        let sliderTouch = panGesture.location(in: nil)
        if (getPlayerSideSliderFrames?() ?? []).contains(where: { $0.contains(sliderTouch) }) {
            return false
        }

        // Don't begin dismiss gesture when dragging portrait panel
        if isPanelDragging?() == true {
            return false
        }

        // Corner layout: don't begin dismiss gesture from inside the
        // below-video panel — its drag handle hides the panel instead
        let belowPanelFrame = getCornerBelowPanelFrame?() ?? .zero
        if !belowPanelFrame.isEmpty {
            let touchLocation = panGesture.location(in: nil)
            if belowPanelFrame.contains(touchLocation) {
                return false
            }
        }

        // Don't begin dismiss gesture from the panel resize grabber strip —
        // a diagonal resize drag would otherwise be cancelled mid-resize
        let grabberFrame = getPanelResizeGrabberFrame?() ?? .zero
        if !grabberFrame.isEmpty {
            let touchLocation = panGesture.location(in: nil)
            if grabberFrame.contains(touchLocation) {
                return false
            }
        }

        // When portrait panel is visible, only allow dismiss from player area (above panel)
        // This prevents race conditions where isPanelDragging isn't set yet when gesture begins
        let panelFrame = getPortraitPanelFrame?() ?? .zero
        let panelVisible = isPortraitPanelVisible?() ?? true
        if !panelFrame.isEmpty && panelVisible {
            let touchLocation = panGesture.location(in: nil) // screen coordinates
            // Block if touch is at or below the panel's top edge
            // This ensures dismiss only works on the player area
            if touchLocation.y >= panelFrame.minY {
                return false
            }
        }

        let velocity = panGesture.velocity(in: gestureRecognizer.view)
        // Only for downward gestures
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    // Allow simultaneous recognition with scroll views
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Our pinch gesture should recognize simultaneously with everything
        // This allows SwiftUI's MagnificationGesture to also receive the touches
        if gestureRecognizer is UIPinchGestureRecognizer {
            return true
        }

        // Pan gesture should not recognize simultaneously with pinch gestures
        if gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer {
            return false
        }

        // Track the scroll view if we find one
        if let scrollView = otherGestureRecognizer.view as? UIScrollView, trackedScrollView == nil {
            trackScrollView(scrollView)
        }
        return true
    }

    // Block pan gesture from receiving touches on slider and progress bar controls
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only filter for pan gestures (our dismiss gesture)
        guard gestureRecognizer is UIPanGestureRecognizer else { return true }

        // Check if touch is within progress bar frame (coordinate-based detection)
        // This is needed because SwiftUI overlays are transparent to UIKit hit-testing
        if let progressBarFrame = getProgressBarFrame?(), progressBarFrame != .zero {
            let locationInWindow = touch.location(in: window)
            // Convert window location to screen coordinates
            if let window = window {
                let locationInScreen = window.convert(locationInWindow, to: nil)
                if progressBarFrame.contains(locationInScreen) {
                    return false
                }
            }
        }

        // Check if touch is on a slider (hit-test based detection)
        let location = touch.location(in: window)
        if let hitView = window?.hitTest(location, with: nil) {
            // Walk up the view hierarchy to find if we're touching a slider
            var view: UIView? = hitView
            while let currentView = view {
                // Check for UISlider (SwiftUI Slider wraps this on iOS)
                if currentView is UISlider {
                    return false
                }
                // Check class name for SwiftUI slider hosting views
                let className = String(describing: type(of: currentView))
                if className.contains("Slider") {
                    return false
                }
                view = currentView.superview
            }
        }
        return true
    }
}

@MainActor
final class ExpandedPlayerWindowManager {
    static let shared = ExpandedPlayerWindowManager()

    private var expandedWindow: UIWindow?
    private weak var appEnvironment: AppEnvironment?
    private var dragHandler: DragToDismissGestureHandler?
    /// Whether a hide is in flight (window still up, cleanup pending).
    private var isHiding = false
    /// Whether the morph has ended and the window waits for the mini player to
    /// adopt the video view before hiding (any hide meanwhile must not animate).
    private var isHandingOffToMiniPlayer = false
    private var pendingHandOffHideCompletions: [() -> Void] = []

    // MARK: - Window Scaling Effect (Apple Music-style)

    /// How much to scale down the main window (0.1 = 10% smaller)
    private let maxScaleProgress: CGFloat = 0.08
    /// Corner radius when fully scaled
    private let scaledCornerRadius: CGFloat = 50

    /// Cached reference to the view we're scaling (first subview of main window)
    /// We cache this to ensure we always reset the same view we scaled
    private weak var scaledPresentingView: UIView?
    
    /// Tracks whether orientation changed during this player session
    /// When rotation occurs, we skip animated scale reset to avoid frame glitches
    private var didRotateDuringSession = false
    
    /// Tracks if scale was skipped during show() because app was inactive
    /// When true, we need to apply scale once app becomes active
    private var pendingScaleApplication = false

    /// Pending show request when scene wasn't ready (for retry)
    private var pendingShowRequest: (appEnvironment: AppEnvironment, animated: Bool)?

    /// Retry count for show() when scene isn't ready (max 3)
    private var showRetryCount = 0
    private let maxShowRetries = 3

    private var backgroundObserver: (any NSObjectProtocol)?
    private var foregroundObserver: (any NSObjectProtocol)?

    private init() {
        setupBackgroundObservers()
    }

    private func setupBackgroundObservers() {
        // Reset main window transform when app goes to background
        // This prevents visual glitches in the app switcher
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }

                // If player is expanded when going inactive (e.g., Control Center),
                // mark that we went through a transition. This ensures we use immediate
                // reset on dismiss instead of animated, avoiding transform glitches.
                if self.expandedWindow != nil {
                    self.didRotateDuringSession = true
                    LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] willResignActive: player expanded, marking didRotateDuringSession=true")
                }

                self.resetMainWindowImmediate()
            }
        }

        // Re-apply main window transform when app comes back to foreground
        // (if the expanded player is still showing)
        // Also processes any pending show requests that failed due to scene not being ready
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Check if we have a pending show request from when scene wasn't ready
                if let pending = self.pendingShowRequest {
                    LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] didBecomeActive: processing pending show request")
                    self.pendingShowRequest = nil
                    // Small delay to ensure scene is fully active
                    try? await Task.sleep(for: .milliseconds(50))
                    self.show(with: pending.appEnvironment, animated: pending.animated)
                } else if self.expandedWindow != nil {
                    // Check if we need to apply scale that was deferred during show()
                    if self.pendingScaleApplication {
                        self.pendingScaleApplication = false
                        // Animate the scale application since we deferred it
                        UIView.animate(withDuration: 0.25) {
                            self.scaleMainWindow(progress: 1.0)
                        }
                        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] didBecomeActive: applied deferred scale (animated)")
                    } else if !self.didRotateDuringSession {
                        // Re-apply scale if no transition occurred (Control Center, etc.)
                        // If didRotateDuringSession is true, we already reset in willResignActive
                        // and should NOT re-apply the scale to avoid frame corruption on dismiss
                        self.scaleMainWindow(progress: 1.0)
                        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] didBecomeActive: re-applied scale")
                    } else {
                        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] didBecomeActive: skipping scale (didRotateDuringSession=true)")
                    }
                } else {
                    // Player was closed - ensure transform is reset
                    self.resetMainWindowImmediate()
                }
            }
        }
    }

    // MARK: - Main Window Scaling

    /// The main app window (the one behind the expanded player)
    private var mainWindow: UIWindow? {
        // Try to find window from any available scene (not just foregroundActive)
        // This handles Control Center being open (foregroundInactive) and other transitions
        let allScenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene: UIWindowScene? = allScenes.first { $0.activationState == .foregroundActive }
        let inactiveScene: UIWindowScene? = allScenes.first { $0.activationState == .foregroundInactive }
        let windowScene: UIWindowScene? = activeScene ?? inactiveScene

        guard let windowScene else {
            LoggingService.shared.logPlayer("[WindowScale] mainWindow: no suitable window scene found")
            return nil
        }

        // Find the main window (not our expanded player window)
        let expandedWin = expandedWindow
        let window = windowScene.windows.first { $0 !== expandedWin && $0.windowLevel == .normal }

        if window == nil {
            LoggingService.shared.logPlayer("[WindowScale] mainWindow: no main window found in scene (state: \(windowScene.activationState.rawValue))")
        }

        return window
    }

    /// Applies scale and corner radius to main window based on progress (0 = normal, 1 = fully scaled)
    func scaleMainWindow(progress: CGFloat) {
        // Capture the presenting view reference on first call
        if scaledPresentingView == nil {
            scaledPresentingView = mainWindow?.subviews.first
            LoggingService.shared.logPlayer("[WindowScale] Captured presentingView: \(String(describing: scaledPresentingView)), bounds: \(scaledPresentingView?.bounds ?? .zero)")
        }
        
        guard let presentingView = scaledPresentingView else {
            LoggingService.shared.logPlayer("[WindowScale] scaleMainWindow(\(progress)) - NO presentingView!")
            return
        }

        // Clamp progress to 0-1 range
        let clampedProgress = max(0, min(1, progress))

        // Calculate actual scale progress (e.g., 0.08 means scale to 0.92)
        let scaleAmount = clampedProgress * maxScaleProgress
        let scale = 1 - scaleAmount

        // Offset to keep the view centered vertically after scaling
        let offsetY = (presentingView.bounds.height * scaleAmount) / 2

        // Apply corner radius proportional to progress
        presentingView.layer.cornerRadius = clampedProgress * scaledCornerRadius
        presentingView.layer.masksToBounds = true

        // Apply scale and translation transform
        presentingView.transform = CGAffineTransform.identity
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: 0, y: offsetY)
    }

    /// Animates main window scale to target progress with spring animation
    func scaleMainWindowAnimated(to progress: CGFloat, duration: TimeInterval = 0.3, damping: CGFloat = 0.7) {
        guard let presentingView = scaledPresentingView ?? mainWindow?.subviews.first else { return }
        
        let clampedProgress = max(0, min(1, progress))
        let scaleAmount = clampedProgress * maxScaleProgress
        let scale = 1 - scaleAmount
        let offsetY = (presentingView.bounds.height * scaleAmount) / 2
        let cornerRadius = clampedProgress * scaledCornerRadius
        
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: damping, initialSpringVelocity: 0, options: []) {
            presentingView.transform = CGAffineTransform.identity
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: 0, y: offsetY)
            presentingView.layer.cornerRadius = cornerRadius
        }
    }

    /// Resets main window to normal state immediately
    func resetMainWindowImmediate() {
        // Reset ALL subviews of the main window to handle rotation edge cases
        // During rotation, UIKit may replace/rearrange transition views
        guard let window = mainWindow else {
            scaledPresentingView = nil
            return
        }

        for subview in window.subviews {
            // Remove any in-flight animations
            subview.layer.removeAllAnimations()
            subview.layer.cornerRadius = 0
            subview.transform = .identity

            // Reset frame to match window bounds (fix any rotation-induced frame issues)
            subview.frame = window.bounds

            // Force layout to apply changes immediately
            subview.setNeedsLayout()
            subview.layoutIfNeeded()

            // Reset clipping
            subview.clipsToBounds = false
            subview.layer.masksToBounds = false
        }

        // Force the window itself to layout
        window.setNeedsLayout()
        window.layoutIfNeeded()

        // Clear the cached reference
        scaledPresentingView = nil
    }
    
    /// Called when rotation occurs during the player session (via viewWillTransition)
    /// This works for both system auto-rotate AND manual fullscreen toggle
    private func handleRotationDuringSession() {
        guard expandedWindow != nil else { return }
        
        // Mark that rotation is in progress - this temporarily disables scale effects
        didRotateDuringSession = true
        
        // Immediately reset main window transforms to prevent frame corruption
        resetMainWindowImmediate()
        
        LoggingService.shared.logPlayer("[WindowScale] handleRotationDuringSession: rotation detected, reset transforms")
        
        // After rotation animation completes, re-apply scale effect so drag-to-dismiss works
        // Use a delay to let the system rotation animation settle
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.expandedWindow != nil else { return }
            
            // Re-apply scale effect with animation
            self.didRotateDuringSession = false
            UIView.animate(withDuration: 0.25) {
                self.scaleMainWindow(progress: 1.0)
            }
            LoggingService.shared.logPlayer("[WindowScale] handleRotationDuringSession: rotation settled, re-applied scale")
        }
    }

    func show(with appEnvironment: AppEnvironment, animated: Bool = true) {
        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show called, expandedWindow=\(expandedWindow != nil), animated=\(animated), retryCount=\(showRetryCount)")
        guard expandedWindow == nil else { return }

        self.appEnvironment = appEnvironment

        // Get the active window scene - allow foregroundInactive for Control Center scenarios
        let allScenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene: UIWindowScene? = allScenes.first { $0.activationState == .foregroundActive }
        let inactiveScene: UIWindowScene? = allScenes.first { $0.activationState == .foregroundInactive }
        let windowScene: UIWindowScene? = activeScene ?? inactiveScene

        guard let windowScene else {
            // Scene not ready - retry if we haven't exceeded max retries
            if showRetryCount < maxShowRetries {
                showRetryCount += 1
                LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show: no suitable window scene, scheduling retry \(showRetryCount)/\(maxShowRetries)")
                pendingShowRequest = (appEnvironment, animated)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, let pending = self.pendingShowRequest else { return }
                    self.pendingShowRequest = nil
                    self.show(with: pending.appEnvironment, animated: pending.animated)
                }
            } else {
                // Exceeded max retries - give up and reset state
                LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show: FAILED after \(maxShowRetries) retries, resetting state")
                showRetryCount = 0
                pendingShowRequest = nil
                appEnvironment.navigationCoordinator.isPlayerExpanded = false
            }
            return
        }

        // Success - clear retry state
        showRetryCount = 0
        pendingShowRequest = nil

        // Create a new window at a level above normal content but below alerts
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .normal + 1  // Above main content, below fullscreen player
        window.backgroundColor = .clear  // Clear for dismiss gesture; SwiftUI provides background

        // Create status bar controller; seed the bar height while the main
        // UI still shows it (the player may hide it before any layout reads it)
        let statusBarController = StatusBarVisibilityController()
        statusBarController.rememberStatusBarHeight(windowScene.statusBarManager?.statusBarFrame.height ?? 0)

        // Create the expanded player view with status bar controller in environment
        // Seed the portrait panel state before the first frame so the preset's
        // default visibility doesn't animate a video position jump on expand.
        let initialPanelVisible = ExpandedPlayerSheet.initialPortraitPanelVisibility(
            settingsManager: appEnvironment.settingsManager
        )
        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show: initialPortraitPanelVisible=\(initialPanelVisible), portraitDefaultVisibility=\(PanelSettings.cached.effectiveDefaultVisibility(for: .portrait))")
        let expandedView = ExpandedPlayerSheet(initialPortraitPanelVisible: initialPanelVisible)
            .appEnvironment(appEnvironment)
            .environment(\.statusBarVisibilityController, statusBarController)

        let hostingController = ExpandedPlayerHostingController(
            rootView: expandedView,
            statusBarController: statusBarController
        )
        // Add safe area insets for tab bar to help PiP avoid covering it
        // Using 50pt as conservative value (inline/minimized tab bar height)
        hostingController.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 46, right: 0)
        hostingController.view.backgroundColor = .clear
        // Ensure the hosting controller's view resizes with the window during rotation
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Handle rotation transitions - reset main window transforms immediately
        // This works for both system auto-rotate AND manual fullscreen toggle
        hostingController.onRotationTransition = { [weak self] in
            self?.handleRotationDuringSession()
        }

        // Set viewController reference so controller can trigger updates
        statusBarController.viewController = hostingController

        window.rootViewController = hostingController

        // Add drag-to-dismiss gesture to the window
        let handler = DragToDismissGestureHandler()
        handler.window = window
        handler.onHapticFeedback = { [weak self] in
            self?.appEnvironment?.settingsManager.triggerHapticFeedback(for: .playerDismiss)
        }
        handler.onDismiss = { [weak self] in
            self?.dismissFromGesture()
        }
        handler.onDismissGestureStateChanged = { [weak self] isActive in
            self?.appEnvironment?.navigationCoordinator.isPlayerDismissGestureActive = isActive
        }
        // Panscan callbacks - connect UIKit pinch gesture to NavigationCoordinator
        handler.onPanscanChanged = { [weak self] panscan in
            self?.appEnvironment?.navigationCoordinator.pinchPanscan = panscan
        }
        handler.onPinchGestureStateChanged = { [weak self] isActive in
            self?.appEnvironment?.navigationCoordinator.isPinchGestureActive = isActive
        }
        handler.getCurrentPanscan = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.pinchPanscan ?? 0.0
        }
        handler.shouldSnapPanscan = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.shouldSnapPanscan ?? true
        }
        handler.isPanelPinnedAndVisible = { [weak self] in
            guard let settings = self?.appEnvironment?.settingsManager else { return false }
            return settings.landscapeDetailsPanelPinned && settings.landscapeDetailsPanelVisible
        }
        handler.isCommentsExpanded = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.isCommentsExpanded ?? false
        }
        handler.isAdjustingPlayerSliders = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.isAdjustingPlayerSliders ?? false
        }
        handler.isPanelDragging = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.isPanelDragging ?? false
        }
        handler.getPortraitPanelFrame = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.portraitPanelFrame ?? .zero
        }
        handler.getCornerBelowPanelFrame = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.cornerBelowPanelFrame ?? .zero
        }
        handler.getPanelResizeGrabberFrame = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.panelResizeGrabberFrame ?? .zero
        }
        handler.getPlayerSideSliderFrames = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.playerSideSliderFrames.values.filter { !$0.isEmpty } ?? []
        }
        handler.isPortraitPanelVisible = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.isPortraitPanelVisible ?? true
        }
        handler.getProgressBarFrame = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.progressBarFrame ?? .zero
        }
        handler.isSeekGestureActive = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.isSeekGestureActive ?? false
        }
        handler.getCommentsFrame = { [weak self] in
            self?.appEnvironment?.navigationCoordinator.commentsFrame ?? .zero
        }
        // Main window scaling callbacks for interactive drag
        handler.onMainWindowScaleChanged = { [weak self] progress in
            guard let self else { return }
            // Skip scaling if a transition occurred (Control Center, etc.)
            // to prevent re-applying transforms after we've reset them
            guard !self.didRotateDuringSession else { return }
            self.scaleMainWindow(progress: progress)
        }
        // Animated scale callback for snap-back
        handler.onMainWindowScaleAnimated = { [weak self] progress in
            guard let self else { return }
            guard !self.didRotateDuringSession else { return }
            self.scaleMainWindowAnimated(to: progress)
        }
        self.dragHandler = handler

        let panGesture = UIPanGestureRecognizer(target: handler, action: #selector(DragToDismissGestureHandler.handlePan(_:)))
        panGesture.delegate = handler

        // Add a pinch gesture recognizer for panscan
        let pinchGesture = UIPinchGestureRecognizer(target: handler, action: #selector(DragToDismissGestureHandler.handlePinch(_:)))
        pinchGesture.delegate = handler
        window.addGestureRecognizer(pinchGesture)

        window.addGestureRecognizer(panGesture)

        // Set frame to match scene bounds (supports iPad Stage Manager / Split View)
        window.frame = windowScene.coordinateSpace.bounds
        window.makeKeyAndVisible()

        self.expandedWindow = window
        
        // Check if app is active BEFORE animation - if not active (e.g., Control Center open),
        // we skip the scale effect and apply it later when app becomes active
        let isAppActive = UIApplication.shared.applicationState == .active
        pendingScaleApplication = !isAppActive
        if !isAppActive {
            LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show: app not active, deferring scale effect")
        }

        if animated {
            // Mark that sheet is animating to defer aspect ratio animation
            appEnvironment.navigationCoordinator.isPlayerSheetAnimating = true
            appEnvironment.navigationCoordinator.isPlayerExpanding = true

            // Start off-screen using transform (more reliable than frame animation)
            let sceneHeight = windowScene.coordinateSpace.bounds.height
            hostingController.view.transform = CGAffineTransform(translationX: 0, y: sceneHeight)

            // Force layout before animating
            hostingController.view.layoutIfNeeded()

            // Animate up - fast and smooth without bounce
            // Also animate main window scaling down (Apple Music-style effect) - but only if app is active
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: []) {
                hostingController.view.transform = .identity
                if isAppActive {
                    self.scaleMainWindow(progress: 1.0)
                }
            } completion: { _ in
                // Sheet animation complete
                appEnvironment.navigationCoordinator.isPlayerSheetAnimating = false
                appEnvironment.navigationCoordinator.isPlayerExpanding = false
                appEnvironment.navigationCoordinator.isPlayerWindowVisible = true
                LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show animation complete, isPlayerWindowVisible=true")
            }
        } else {
            // No animation - apply scale immediately (only if app is active)
            if isAppActive {
                scaleMainWindow(progress: 1.0)
            }
            appEnvironment.navigationCoordinator.isPlayerExpanding = false
            appEnvironment.navigationCoordinator.isPlayerWindowVisible = true
            LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show complete (no animation), isPlayerWindowVisible=true")
        }

        // Notify player service
        appEnvironment.playerService.playerSheetDidAppear()

        // Trigger haptic feedback
        if animated {
            appEnvironment.settingsManager.triggerHapticFeedback(for: .playerShow)
        }

        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] show complete")
    }

    /// Drag-to-dismiss released past the threshold: morph the video into the
    /// mini player when its preview is on screen, otherwise slide off screen.
    private func dismissFromGesture() {
        guard let nav = appEnvironment?.navigationCoordinator else { return }

        if morphIntoMiniPlayer(completion: { [weak self] in
            self?.handOffToMiniPlayer()
        }) {
            return
        }

        // Slide off: hide() animates from the dragged position and marks the
        // window not visible before the gesture flag clears (no black overlay
        // frame). isPlayerExpanded flips last, so the mini player doesn't take
        // the video view from the sliding window.
        expandedWindow?.isUserInteractionEnabled = false
        hide(animated: true) {
            nav.isPlayerExpanded = false
        }
        nav.isPlayerDismissGestureActive = false
    }

    /// Ends the morph: un-expands so the mini player mounts its video view, and
    /// hides the window only once that view has actually moved into the mini
    /// player. SwiftUI may mount it a frame later; hiding first left a frame
    /// with neither (a blank preview).
    private func handOffToMiniPlayer() {
        guard let nav = appEnvironment?.navigationCoordinator else { return }
        let playerView = (appEnvironment?.playerService.currentBackend as? MPVBackend)?.playerView

        nonisolated(unsafe) var observer: (any NSObjectProtocol)?
        let finish: () -> Void = { [weak self] in
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            nav.isPlayerMorphingToMini = false
            guard let self, self.isHandingOffToMiniPlayer else { return }
            self.isHandingOffToMiniPlayer = false
            // Hide now, in the same pass the mini player adopts the view; the full
            // cleanup (layout passes, orientation) runs outside that SwiftUI update
            self.expandedWindow?.isHidden = true
            let completions = self.pendingHandOffHideCompletions
            self.pendingHandOffHideCompletions = []
            DispatchQueue.main.async { [weak self] in
                self?.hide(animated: false) {
                    completions.forEach { $0() }
                }
            }
        }

        isHandingOffToMiniPlayer = true
        if let playerView, playerView.window === expandedWindow {
            // Adopting isn't enough: the view keeps its old size and the new
            // container is still zero-sized until the next layout pass, so the
            // preview is blank for a frame. Wait until it's laid out there.
            observer = NotificationCenter.default.addObserver(
                forName: .mpvPlayerViewDidChangeContainer, object: playerView, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    observer = nil
                    self?.waitUntilLaidOutInMiniPlayer(playerView, then: finish)
                }
            }
            // Fallback when the mini player never takes the view (video hidden in it)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { finish() }
        } else {
            DispatchQueue.main.async { finish() }
        }

        nav.isPlayerDismissGestureActive = false
        nav.isPlayerCollapsing = true
        nav.isPlayerExpanded = false
    }

    /// Calls `then` on the first display frame after the player view sits,
    /// sized, in a container outside the expanded window: by then that layout
    /// pass has re-rendered it into its resized framebuffer.
    private func waitUntilLaidOutInMiniPlayer(_ playerView: UIView, then: @escaping () -> Void) {
        let isLaidOut = { [weak self] in
            let size = playerView.bounds.size
            return playerView.window != nil
                && playerView.window !== self?.expandedWindow
                && size.width > 1 && size.height > 1
                && playerView.superview?.bounds.size == size
        }
        // The container adopts it already sized and redrawn: hide right away,
        // in the same frame (the window has a black hole where the video was)
        if isLaidOut() {
            then()
            return
        }
        var wasLaidOut = false
        let ticker = DisplayLinkTicker()
        ticker.start { [weak self] in
            guard let self, self.isHandingOffToMiniPlayer else {
                ticker.stop()
                return
            }
            if wasLaidOut {
                ticker.stop()
                then()
            }
            wasLaidOut = isLaidOut()
        }
    }

    /// Makes the main window's SwiftUI content pick up its current safe area
    /// (setNeedsLayout alone doesn't invalidate SwiftUI's cached insets).
    private func refreshMainWindowSafeArea() {
        guard let rootVC = mainWindow?.rootViewController else { return }
        let insets = rootVC.additionalSafeAreaInsets
        rootVC.additionalSafeAreaInsets = UIEdgeInsets(top: insets.top + 1, left: insets.left, bottom: insets.bottom, right: insets.right)
        rootVC.additionalSafeAreaInsets = insets
        rootVC.view.setNeedsLayout()
        rootVC.view.layoutIfNeeded()
    }

    /// Shrinks the expanded window onto its video and flies it into the mini
    /// player's video preview. Returns false (doing nothing) when no target is
    /// available, so the caller falls back to sliding off screen.
    private func morphIntoMiniPlayer(completion: @escaping () -> Void) -> Bool {
        guard let window = expandedWindow,
              let hostView = window.rootViewController?.view,
              let nav = appEnvironment?.navigationCoordinator,
              !didRotateDuringSession,
              let playerView = (appEnvironment?.playerService.currentBackend as? MPVBackend)?.playerView,
              playerView.window === window,
              mainWindow.map({ $0.bounds.size == window.bounds.size }) == true else {
            return false
        }

        // The mini player reports its SwiftUI global frame, which ignores the scale
        // transform on the main window's content (that animates back to identity
        // alongside the morph), so it is already where the mini player ends up.
        // The scaled content did get a smaller bottom safe area (UIKit derives it
        // from the transformed frame), which comes back once unscaled and lifts
        // the bottom-anchored mini player by the difference.
        var target = nav.miniPlayerVideoFrame
        if let mainWindow, let mainRootView = mainWindow.rootViewController?.view {
            target.origin.y -= max(0, mainWindow.safeAreaInsets.bottom - mainRootView.safeAreaInsets.bottom)
        }
        let renderRect = playerView.convert(playerView.bounds, to: window)
        let source = visibleVideoRect(in: renderRect, panelFrame: hostView.convert(nav.portraitPanelFrame, to: window), nav: nav)
        guard target.width > 1, target.height > 1, window.bounds.contains(target),
              source.width > 1, source.height > 1 else {
            return false
        }

        // The mask doesn't stop hit testing: keep stray touches off the hidden controls
        window.isUserInteractionEnabled = false
        hostView.layer.removeAllAnimations()
        nav.isPlayerMorphingToMini = true
        nav.isPlayerWindowVisible = false

        // Only the video morphs: the window mask keeps the video opaque as it
        // flies to the target and fades everything around it (title, panels) out.
        // The window keeps its drag offset and animates back to 0 alongside the
        // morph; content and mask share that offset, so both are expressed in
        // un-offset window coordinates. (Transforming the UIWindow itself stops
        // it rendering.)
        let mask = UIView(frame: window.bounds)
        let surroundingMask = UIView(frame: window.bounds)
        surroundingMask.backgroundColor = .black
        let videoMask = UIView(frame: source)
        videoMask.backgroundColor = .black
        videoMask.layer.cornerCurve = .continuous
        mask.addSubview(surroundingMask)
        mask.addSubview(videoMask)
        window.mask = mask

        // Map the source rect onto the target rect (a view transform applies about its center)
        let center = hostView.center
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let finalTransform = CGAffineTransform(
            a: scaleX, b: 0, c: 0, d: scaleY,
            tx: target.midX - center.x - scaleX * (source.midX - center.x),
            ty: target.midY - center.y - scaleY * (source.midY - center.y)
        )

        // UIKit derives a view's safe area from its transformed frame: once scaled
        // toward the mini player the host no longer overlaps the status bar, its
        // top inset drops to 0 and SwiftUI re-lays the player out higher — out
        // from under the mask. Capture the insets to pin them below.
        let insetsBefore = hostView.safeAreaInsets

        UIView.animate(withDuration: 0.15) {
            surroundingMask.alpha = 0
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: []) {
            window.frame.origin.y = 0
            hostView.transform = finalTransform
            videoMask.frame = target
            videoMask.layer.cornerRadius = nav.miniPlayerVideoCornerRadius
            self.scaleMainWindow(progress: 0)
        } completion: { _ in
            completion()
        }

        // Unscaled, the main content gets its full safe area back: re-lay it out
        // now, under the morphing video, rather than with a late jump at the end
        refreshMainWindowSafeArea()

        // Pin the safe area: add back whatever the transform took away
        if let hostingController = window.rootViewController {
            window.layoutIfNeeded()
            let insetsAfter = hostView.safeAreaInsets
            let additional = hostingController.additionalSafeAreaInsets
            hostingController.additionalSafeAreaInsets = UIEdgeInsets(
                top: additional.top + insetsBefore.top - insetsAfter.top,
                left: additional.left + insetsBefore.left - insetsAfter.left,
                bottom: additional.bottom + insetsBefore.bottom - insetsAfter.bottom,
                right: additional.right + insetsBefore.right - insetsAfter.right
            )
            hostView.layoutIfNeeded()
        }
        return true
    }

    /// The part of the render view that shows video: the aspect-fit picture,
    /// minus whatever the portrait details panel covers.
    private func visibleVideoRect(in renderRect: CGRect, panelFrame panel: CGRect, nav: NavigationCoordinator) -> CGRect {
        let aspect = CGFloat(appEnvironment?.playerService.state.displayAspectRatio ?? 16.0 / 9.0)
        var rect = renderRect
        if aspect > 0 {
            if renderRect.width / renderRect.height > aspect {
                let width = renderRect.height * aspect
                rect = CGRect(x: renderRect.midX - width / 2, y: renderRect.minY, width: width, height: renderRect.height)
            } else {
                let height = renderRect.width / aspect
                rect = CGRect(x: renderRect.minX, y: renderRect.midY - height / 2, width: renderRect.width, height: height)
            }
        }
        if nav.isPortraitPanelVisible, panel.height > 0, panel.minY < rect.maxY, panel.minY > rect.minY {
            rect.size.height = panel.minY - rect.minY
        }
        return rect
    }

    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] hide called, expandedWindow=\(expandedWindow != nil), animated=\(animated)")

        // Clear any pending show request and scale application
        pendingShowRequest = nil
        showRetryCount = 0
        pendingScaleApplication = false

        appEnvironment?.navigationCoordinator.isPlayerWindowVisible = false

        guard let window = expandedWindow else {
            completion?()
            return
        }

        // The morphed window sits on the mini player until the mini player has
        // laid out the video; the handoff hides it then
        if isHandingOffToMiniPlayer {
            if let completion {
                pendingHandOffHideCompletions.append(completion)
            }
            return
        }

        // A hide is already running (e.g. the gesture's hide followed by the
        // isPlayerExpanded onChange); a second one would clean up twice
        guard !isHiding else {
            completion?()
            return
        }
        isHiding = true
        // Start collapsing animation
        appEnvironment?.navigationCoordinator.isPlayerCollapsing = true
        LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] hide: isPlayerWindowVisible=false, isPlayerCollapsing=true")

        let cleanup: () -> Void = { [weak self] in
            LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] hide: cleanup")
            self?.isHiding = false

            // Always ensure main window transform is fully reset (safeguard against race conditions)
            self?.resetMainWindowImmediate()
            
            // Reset rotation tracking
            self?.didRotateDuringSession = false
            
            // Reset collapsing state
            self?.appEnvironment?.navigationCoordinator.isPlayerCollapsing = false
            
            self?.dragHandler = nil
            self?.expandedWindow?.isHidden = true
            self?.expandedWindow?.rootViewController = nil
            self?.expandedWindow = nil

            // Notify player service
            self?.appEnvironment?.playerService.playerSheetDidDisappear()

            // Tell main window to re-check orientation support and rotate if needed
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {

                // Update all windows' root view controllers
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }

                // Force SwiftUI safe area recalculation by toggling additionalSafeAreaInsets
                // setNeedsStatusBarAppearanceUpdate() alone doesn't invalidate SwiftUI's safe area cache
                for window in windowScene.windows where window != self?.expandedWindow {
                    if let rootVC = window.rootViewController {
                        // Toggle additionalSafeAreaInsets to force SwiftUI geometry recalculation
                        let originalInsets = rootVC.additionalSafeAreaInsets
                        rootVC.additionalSafeAreaInsets = UIEdgeInsets(
                            top: originalInsets.top + 1,
                            left: originalInsets.left,
                            bottom: originalInsets.bottom,
                            right: originalInsets.right
                        )
                        rootVC.additionalSafeAreaInsets = originalInsets

                        // Also trigger layout invalidation
                        rootVC.setNeedsStatusBarAppearanceUpdate()
                        rootVC.view.setNeedsLayout()
                        rootVC.view.layoutIfNeeded()
                    }
                }

                // If device is in portrait OR preferPortraitBrowsing is enabled, request portrait rotation
                let screenBounds = windowScene.screen.bounds
                let isScreenLandscape = screenBounds.width > screenBounds.height
                let isDevicePortrait = DeviceRotationManager.shared.isPortrait
                let preferPortrait = self?.appEnvironment?.settingsManager.preferPortraitBrowsing ?? false

                LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] Dismiss rotation check: isScreenLandscape=\(isScreenLandscape), isDevicePortrait=\(isDevicePortrait), preferPortrait=\(preferPortrait)")

                if isScreenLandscape && (isDevicePortrait || preferPortrait) {
                    LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] Requesting portrait rotation on dismiss")
                    // Lock to portrait to force rotation, then unlock after a short delay
                    OrientationManager.shared.lock(to: .portrait)
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                    
                    // Unlock after rotation completes so user can rotate freely again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        OrientationManager.shared.unlock()
                    }
                }
            }

            completion?()
            LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] hide complete")
        }

        if animated {
            // If rotation occurred during this session, skip the animated scale reset
            // because the main window's UITransitionView has a corrupted frame after rotation
            let shouldAnimateMainWindow = !didRotateDuringSession
            
            LoggingService.shared.logPlayer("[ExpandedPlayerWindowManager] hide: animated=\(animated), didRotateDuringSession=\(didRotateDuringSession), shouldAnimateMainWindow=\(shouldAnimateMainWindow)")
            
            // Animate down - fast and smooth without bounce
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: [], animations: {
                window.frame.origin.y = window.bounds.height
                if shouldAnimateMainWindow {
                    // Only animate scale if no rotation occurred
                    self.scaleMainWindow(progress: 0)
                }
            }, completion: { _ in
                cleanup()
            })
        } else {
            resetMainWindowImmediate()
            cleanup()
        }
    }
}
#endif

#if os(iOS)
/// Runs a closure once per display frame until stopped.
@MainActor
private final class DisplayLinkTicker: NSObject {
    private var displayLink: CADisplayLink?
    private var tick: (() -> Void)?

    func start(_ tick: @escaping () -> Void) {
        self.tick = tick
        let link = CADisplayLink(target: self, selector: #selector(fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        tick = nil
    }

    @objc private func fire() {
        tick?()
    }
}
#endif
