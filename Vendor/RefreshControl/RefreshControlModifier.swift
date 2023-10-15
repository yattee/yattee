//
//  RefreshControlModifier.swift
//  SwiftUI_Pull_to_Refresh
//
//  Created by Geri Borbás on 18/09/2021.
//

import Foundation
import SwiftUI

struct RefreshControlModifier: ViewModifier {
    @State private var geometryReaderFrame: CGRect = .zero
    let refreshControl: RefreshControl

    init(onValueChanged: @escaping (UIRefreshControl) -> Void) {
        refreshControl = RefreshControl(onValueChanged: onValueChanged)
    }

    func body(content: Content) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            return content
        } else {
            return content
                .background(
                    GeometryReader { geometry in
                        ScrollViewMatcher(
                            onResolve: { scrollView in
                                refreshControl.add(to: scrollView)
                            },
                            geometryReaderFrame: $geometryReaderFrame
                        )
                        .preference(key: FramePreferenceKey.self, value: geometry.frame(in: .global))
                        .onPreferenceChange(FramePreferenceKey.self) { frame in
                            self.geometryReaderFrame = frame
                        }
                    }
                )
        }
    }
}

extension View {
    func refreshControl(onValueChanged: @escaping (_ refreshControl: UIRefreshControl) -> Void) -> some View {
        modifier(RefreshControlModifier(onValueChanged: onValueChanged))
    }
}
