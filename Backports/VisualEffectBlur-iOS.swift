/*
 Copyright © 2020 Apple Inc.
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import SwiftUI

#if os(iOS)
    public struct VisualEffectBlur<Content: View>: View {
        /// Defaults to .systemMaterial
        var blurStyle: UIBlurEffect.Style

        /// Defaults to nil
        var vibrancyStyle: UIVibrancyEffectStyle?

        var content: Content

        public init(blurStyle: UIBlurEffect.Style = .systemMaterial, vibrancyStyle: UIVibrancyEffectStyle? = nil, @ViewBuilder content: () -> Content) {
            self.blurStyle = blurStyle
            self.vibrancyStyle = vibrancyStyle
            self.content = content()
        }

        public var body: some View {
            Representable(blurStyle: blurStyle, vibrancyStyle: vibrancyStyle, content: ZStack { content })
                .accessibility(hidden: Content.self == EmptyView.self)
        }
    }

    // MARK: - Representable

    extension VisualEffectBlur {
        struct Representable<Content: View>: UIViewRepresentable {
            var blurStyle: UIBlurEffect.Style
            var vibrancyStyle: UIVibrancyEffectStyle?
            var content: Content

            func makeUIView(context: Context) -> UIVisualEffectView {
                context.coordinator.blurView
            }

            func updateUIView(_: UIVisualEffectView, context: Context) {
                context.coordinator.update(content: content, blurStyle: blurStyle, vibrancyStyle: vibrancyStyle)
            }

            func makeCoordinator() -> Coordinator {
                Coordinator(content: content)
            }
        }
    }

    // MARK: - Coordinator

    extension VisualEffectBlur.Representable {
        class Coordinator {
            let blurView = UIVisualEffectView()
            let vibrancyView = UIVisualEffectView()
            let hostingController: UIHostingController<Content>

            init(content: Content) {
                hostingController = UIHostingController(rootView: content)
                hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                hostingController.view.backgroundColor = nil
                blurView.contentView.addSubview(vibrancyView)

                blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                vibrancyView.contentView.addSubview(hostingController.view)
                vibrancyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }

            func update(content: Content, blurStyle: UIBlurEffect.Style, vibrancyStyle: UIVibrancyEffectStyle?) {
                hostingController.rootView = content

                let blurEffect = UIBlurEffect(style: blurStyle)
                blurView.effect = blurEffect

                if let vibrancyStyle {
                    vibrancyView.effect = UIVibrancyEffect(blurEffect: blurEffect, style: vibrancyStyle)
                } else {
                    vibrancyView.effect = nil
                }

                hostingController.view.setNeedsDisplay()
            }
        }
    }

    extension VisualEffectBlur where Content == EmptyView {
        init(blurStyle: UIBlurEffect.Style = .systemMaterial) {
            self.init(blurStyle: blurStyle, vibrancyStyle: nil) {
                EmptyView()
            }
        }
    }
#endif
