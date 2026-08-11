//
//  Array+Chunked.swift
//  Yattee
//
//  Splitting arrays into fixed-size chunks.
//

import Foundation

extension Array {
    /// Splits the array into chunks of the specified size.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
