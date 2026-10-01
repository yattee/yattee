//
//  MPVReflectionLayer.swift
//  Yattee
//
//  Layer that shows a vertically mirrored copy of the rendered video frame,
//  used for the "reflection" below the video in the iPhone Duo tabletop
//  layout. The render view feeds it every presented frame.
//

import Foundation
import QuartzCore
import IOSurface

#if canImport(UIKit)
import UIKit

final class MPVReflectionLayer: CALayer {
    override init() {
        super.init()
        contentsGravity = .resizeAspect
        isOpaque = false
        // Frame updates must not trigger implicit fades.
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Show a surface whose rows are already mirrored (GL blit without Y flip).
    func display(_ surface: IOSurface) {
        contents = surface
    }

    /// Show an upright image; the layer mirrors it itself.
    func displayMirrored(_ image: CGImage) {
        if CATransform3DIsIdentity(transform) {
            transform = CATransform3DMakeScale(1, -1, 1)
        }
        contents = image
    }

    func clear() {
        contents = nil
    }
}

#endif
