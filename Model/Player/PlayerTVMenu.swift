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

            return availableStreamsSorted.filter { backend.canPlay($0) }.map { stream in
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
                title: "Restore \(segment.title())",
                image: UIImage(systemName: "arrow.uturn.left.circle")
            ) { _ in
                self.restoreLastSkippedSegment()
            }
        }

        var closeCurrentItemAction: UIAction {
            UIAction(title: "Close video", image: UIImage(systemName: "xmark")) { [weak self] _ in
                self?.closeCurrentItem()
            }
        }

        var switchToMPVAction: UIAction? {
            UIAction(title: "Switch to MPV", image: UIImage(systemName: "m.circle")) { _ in
                self.avPlayerBackend.controller?.dismiss(animated: false)
                self.changeActiveBackend(from: .appleAVPlayer, to: .mpv)
            }
        }

        private var rateMenu: UIMenu {
            UIMenu(title: "Playback rate", image: UIImage(systemName: rateMenuSystemImage), children: rateMenuActions)
        }

        private var rateMenuSystemImage: String {
            [0.0, 1.0].contains(currentRate) ? "speedometer" : (currentRate < 1.0 ? "tortoise.fill" : "hare.fill")
        }

        private var rateMenuActions: [UIAction] {
            PlayerModel.shared.backend.suggestedPlaybackRates.map { rate in
                let image = currentRate == rate ? UIImage(systemName: "checkmark") : nil

                return UIAction(title: rateLabel(rate), image: image) { _ in
                    DispatchQueue.main.async {
                        self.currentRate = rate
                    }
                }
            }
        }

        private var playbackModeMenu: UIMenu {
            UIMenu(title: "Playback Mode", image: UIImage(systemName: playbackMode.systemImage), children: playbackModeMenuActions)
        }

        private var playbackModeMenuActions: [UIAction] {
            PlaybackMode.allCases.map { mode in
                UIAction(title: mode.description, image: UIImage(systemName: mode.systemImage)) { _ in
                    DispatchQueue.main.async {
                        self.playbackMode = mode
                    }
                }
            }
        }
    #endif

    func rebuildTVMenu() {
        #if os(tvOS)
            avPlayerBackend.controller?.playerView.transportBarCustomMenuItems = [
                restoreLastSkippedSegmentAction,
                closeCurrentItemAction,
                rateMenu,
                streamsMenu,
                playbackModeMenu,
                switchToMPVAction
            ].compactMap { $0 }
        #endif
    }
}
