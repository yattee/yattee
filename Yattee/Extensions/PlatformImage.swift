//
//  PlatformImage.swift
//  Yattee
//
//  Cross-platform image typealias.
//

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif
