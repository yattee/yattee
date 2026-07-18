//
//  Video+DeArrow.swift
//  Yattee
//
//  Extension for DeArrow title resolution on Video.
//

import Foundation

extension Video {
    /// Returns the DeArrow-replaced title if available, otherwise the original title.
    ///
    /// Usage: `video.displayTitle(using: appEnvironment?.deArrowBrandingProvider)`
    @MainActor
    func displayTitle(using provider: DeArrowBrandingProvider?) -> String {
        provider?.title(for: self) ?? title
    }
}
