//
//  AirPlayButton.swift
//  Yattee
//
//  SwiftUI wrapper for AVRoutePickerView to show AirPlay device selection.
//

import AVKit
import SwiftUI

#if os(iOS)
import UIKit

struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = tintColor
        routePicker.activeTintColor = .systemBlue
        return routePicker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}

#elseif os(macOS)
import AppKit

struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.isRoutePickerButtonBordered = false
        return routePicker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
