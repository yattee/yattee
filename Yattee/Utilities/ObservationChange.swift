//
//  ObservationChange.swift
//  Yattee
//

import Foundation
import Observation

/// Suspends until a property read in `track` changes, or the task is cancelled.
///
/// Use in an observer loop instead of polling with `Task.sleep`, which keeps
/// waking the main thread for as long as the app runs.
@MainActor
func observationChange(_ track: () -> Void) async {
    let (changes, continuation) = AsyncStream<Void>.makeStream()
    withObservationTracking(track) {
        continuation.yield()
        continuation.finish()
    }
    for await _ in changes { break }
}
