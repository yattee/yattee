//
//  HingeLayoutObserver.swift
//  Yattee
//
//  Observes the foldable device hinge (iPhone Duo) and reports whether the
//  player should use the "tabletop" layout: hinge partially open, device
//  resting like a laptop, video on the upper half and controls on the lower.
//

import SwiftUI

#if os(iOS)

struct HingeLayoutObserver: ViewModifier {
    @Binding var isTabletop: Bool

    /// Debug override: launch with `YATTEE_FORCE_TABLETOP=1` to force the
    /// tabletop layout on simulators without a hinge control.
    private static let forceTabletop = ProcessInfo.processInfo.environment["YATTEE_FORCE_TABLETOP"] == "1"

    func body(content: Content) -> some View {
        if Self.forceTabletop {
            content.onAppear { isTabletop = true }
        } else if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                // `hinge` is nil on devices without a hinge and when the view
                // leaves a hierarchy that provides hinge updates.
                let tabletop = context.hinge?.status == .partiallyOpen
                guard tabletop != isTabletop else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isTabletop = tabletop
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Tracks the device hinge and writes whether the tabletop player layout
    /// should be active. No-op before iOS 27.1 and on devices without a hinge.
    func observeHingeLayout(isTabletop: Binding<Bool>) -> some View {
        modifier(HingeLayoutObserver(isTabletop: isTabletop))
    }
}

#endif
