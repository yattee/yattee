import AVFAudio
import CoreMedia
import Defaults
import Foundation
import SwiftUI

extension PlayerModel {
    func handleSegments(at time: CMTime) {
        if let segment = lastSkipped {
            if time > .secondsInDefaultTimescale(segment.end + 5) {
                resetLastSegment()
            }
        }

        guard let firstSegment = sponsorBlock.segments.first(where: { $0.timeInSegment(time) }) else {
            return
        }

        // find last segment in case they are 2 sec or less after each other
        // to avoid multiple skips in a row
        var nextSegments = [firstSegment]

        while let segment = sponsorBlock.segments.first(where: {
            !nextSegments.contains($0) &&
                $0.timeInSegment(.secondsInDefaultTimescale(nextSegments.last!.end + 2))
        }) {
            nextSegments.append(segment)
        }

        if let segmentToSkip = nextSegments.last, shouldSkip(segmentToSkip, at: time) {
            skip(segmentToSkip, at: time)
        }
    }

    var playerItemEndTimeWithSegments: CMTime? {
        if let duration = playerItemDuration,
           let segment = sponsorBlock.segments.last,
           segment.endTime.seconds >= duration.seconds - 3
        {
            return segment.endTime
        }

        return playerItemDuration
    }

    private func skip(_ segment: Segment, at time: CMTime) {
        backend.seek(to: segment.endTime, seekType: .segmentSkip(segment.category))

        DispatchQueue.main.async { [weak self] in
            withAnimation {
                self?.lastSkipped = segment
            }
            self?.segmentRestorationTime = time
        }
        logger.info("SponsorBlock skipping to: \(segment.end)")

        if let duration = playerItemDuration, segment.endTime.seconds >= duration.seconds - 3 {
            logger.error("Segment end time is: \(segment.end) when player item duration is: \(duration.seconds)")

            DispatchQueue.main.async { [weak self] in
                self?.backend.eofPlaybackModeAction()
            }
        }
    }

    private func shouldSkip(_ segment: Segment, at time: CMTime) -> Bool {
        guard isPlaying,
              !restoredSegments.contains(segment),
              Defaults[.sponsorBlockCategories].contains(segment.category)
        else {
            return false
        }

        return time.seconds - segment.start < 2 && segment.end - time.seconds > 2
    }

    func restoreLastSkippedSegment() {
        guard let segment = lastSkipped,
              let time = segmentRestorationTime
        else {
            return
        }

        restoredSegments.append(segment)
        backend.seek(to: time, seekType: .segmentRestore)
        resetLastSegment()
    }

    private func resetLastSegment() {
        DispatchQueue.main.async { [weak self] in
            withAnimation {
                self?.lastSkipped = nil
                self?.controls.objectWillChange.send()
            }
            self?.segmentRestorationTime = nil
        }
    }

    func resetSegments() {
        resetLastSegment()
        DispatchQueue.main.async { [weak self] in
            self?.restoredSegments = []
        }
    }
}
