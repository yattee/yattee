//
//  MPVReflectionView.swift
//  Yattee
//
//  Hosts the backend's mirrored frame layer below the video in the iPhone
//  Duo tabletop layout, so the lower half shows a dim "reflection" of the
//  upper half like a screen standing on a glossy table.
//

import SwiftUI

#if os(iOS)
import UIKit

/// Shows the mirrored video frames the MPV render view captures while the
/// view is on screen. Sized to the fitted video; place it directly below the
/// hinge line and fade it with `tabletopReflectionOverlay`.
struct MPVReflectionView: UIViewRepresentable {
    let backend: MPVBackend

    func makeUIView(context: Context) -> ReflectionHostView {
        let view = ReflectionHostView()
        view.backend = backend
        view.attach(backend.reflectionLayer)
        backend.setReflectionEnabled(true)
        return view
    }

    func updateUIView(_ uiView: ReflectionHostView, context: Context) {
        // The backend's player view can be recreated; re-attach the current layer.
        uiView.backend = backend
        uiView.attach(backend.reflectionLayer)
        backend.setReflectionEnabled(true)
    }

    static func dismantleUIView(_ uiView: ReflectionHostView, coordinator: ()) {
        uiView.backend?.setReflectionEnabled(false)
        uiView.attach(nil)
    }

    final class ReflectionHostView: UIView {
        private weak var hostedLayer: CALayer?
        weak var backend: MPVBackend?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        func attach(_ newLayer: CALayer?) {
            guard newLayer !== hostedLayer else { return }
            hostedLayer?.removeFromSuperlayer()
            hostedLayer = newLayer
            if let newLayer {
                newLayer.frame = bounds
                layer.addSublayer(newLayer)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hostedLayer?.frame = bounds
            CATransaction.commit()
        }

        deinit {
            hostedLayer?.removeFromSuperlayer()
        }
    }
}

#endif
