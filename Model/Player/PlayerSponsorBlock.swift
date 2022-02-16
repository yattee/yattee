import CoreMedia
import Defaults
import Foundation

extension PlayerModel {
    func handleSegments(at time: CMTime) {
        if let segment = lastSkipped {
            if time > .secondsInDefaultTimescale(segment.end + 10) {
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
            $0.timeInSegment(.secondsInDefaultTimescale(nextSegments.last!.end + 2))
        }) {
            nextSegments.append(segment)
        }

        if let segmentToSkip = nextSegments.last(where: { $0.endTime <= playerItemDuration ?? .zero }),
           self.shouldSkip(segmentToSkip, at: time)
        {
            skip(segmentToSkip, at: time)
        }
    }

    private func skip(_ segment: Segment, at time: CMTime) {
        guard segment.endTime.seconds <= playerItemDuration?.seconds ?? .infinity else {
            logger.error(
                "segment end time is: \(segment.end) when player item duration is: \(playerItemDuration?.seconds ?? .infinity)"
            )
            return
        }

        backend.seek(to: segment.endTime)

        DispatchQueue.main.async { [weak self] in
            self?.lastSkipped = segment
            self?.segmentRestorationTime = time
        }
        logger.info("SponsorBlock skipping to: \(segment.end)")
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
        backend.seek(to: time)
        resetLastSegment()
    }

    private func resetLastSegment() {
        DispatchQueue.main.async { [weak self] in
            self?.lastSkipped = nil
            self?.segmentRestorationTime = nil
        }
    }

    func resetSegments() {
        resetLastSegment()
        restoredSegments = []
    }
}
