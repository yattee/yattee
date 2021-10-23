import Foundation
#if !os(macOS)
    import UIKit
#endif

extension PlayerModel {
    #if os(tvOS)
        var streamsMenu: UIMenu {
            UIMenu(
                title: "Streams",
                image: UIImage(systemName: "antenna.radiowaves.left.and.right"),
                children: streamsMenuActions
            )
        }

        var streamsMenuActions: [UIAction] {
            guard !availableStreams.isEmpty else {
                return [ // swiftlint:disable:this implicit_return
                    UIAction(title: "Empty", attributes: .disabled) { _ in }
                ]
            }

            return availableStreamsSorted.map { stream in
                let state = stream == streamSelection ? UIAction.State.on : .off

                return UIAction(title: stream.description, state: state) { _ in
                    self.streamSelection = stream
                    self.upgradeToStream(stream)
                }
            }
        }

        var restoreLastSkippedSegmentAction: UIAction? {
            guard let segment = lastSkipped else {
                return nil // swiftlint:disable:this implicit_return
            }

            return UIAction(
                title: "Restore \(segment.category)",
                image: UIImage(systemName: "arrow.uturn.left.circle")
            ) { _ in
                self.restoreLastSkippedSegment()
            }
        }
    #endif

    func rebuildTVMenu() {
        #if os(tvOS)
            avPlayerViewController?.transportBarCustomMenuItems = [
                restoreLastSkippedSegmentAction,
                streamsMenu
            ].compactMap { $0 }
        #endif
    }
}
