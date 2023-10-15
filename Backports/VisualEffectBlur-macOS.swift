/*
 Copyright © 2020 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import SwiftUI

#if os(macOS)

    public struct VisualEffectBlur: View {
        private var material: NSVisualEffectView.Material
        private var blendingMode: NSVisualEffectView.BlendingMode
        private var state: NSVisualEffectView.State

        public init(
            material: NSVisualEffectView.Material = .headerView,
            blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
            state: NSVisualEffectView.State = .followsWindowActiveState
        ) {
            self.material = material
            self.blendingMode = blendingMode
            self.state = state
        }

        public var body: some View {
            Representable(
                material: material,
                blendingMode: blendingMode,
                state: state
            ).accessibility(hidden: true)
        }
    }

    // MARK: - Representable

    extension VisualEffectBlur {
        struct Representable: NSViewRepresentable {
            var material: NSVisualEffectView.Material
            var blendingMode: NSVisualEffectView.BlendingMode
            var state: NSVisualEffectView.State

            func makeNSView(context: Context) -> NSVisualEffectView {
                context.coordinator.visualEffectView
            }

            func updateNSView(_: NSVisualEffectView, context: Context) {
                context.coordinator.update(material: material)
                context.coordinator.update(blendingMode: blendingMode)
                context.coordinator.update(state: state)
            }

            func makeCoordinator() -> Coordinator {
                Coordinator()
            }
        }

        class Coordinator {
            let visualEffectView = NSVisualEffectView()

            init() {
                visualEffectView.blendingMode = .withinWindow
            }

            func update(material: NSVisualEffectView.Material) {
                visualEffectView.material = material
            }

            func update(blendingMode: NSVisualEffectView.BlendingMode) {
                visualEffectView.blendingMode = blendingMode
            }

            func update(state: NSVisualEffectView.State) {
                visualEffectView.state = state
            }
        }
    }

#endif
