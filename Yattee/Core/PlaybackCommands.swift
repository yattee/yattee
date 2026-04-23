//
//  PlaybackCommands.swift
//  Yattee
//
//  Menu bar commands for playback control.
//

import SwiftUI

#if !os(tvOS)
/// Playback-related menu bar commands.
/// Works on both macOS and iPadOS 26+.
struct PlaybackCommands: Commands {
    let appEnvironment: AppEnvironment

    private var playerService: PlayerService {
        appEnvironment.playerService
    }

    private var navigationCoordinator: NavigationCoordinator {
        appEnvironment.navigationCoordinator
    }

    private var state: PlayerState {
        playerService.state
    }

    private var settingsManager: SettingsManager {
        appEnvironment.settingsManager
    }

    private var hasActiveVideo: Bool {
        state.currentVideo != nil
    }

    private var isPlayerExpanded: Bool {
        navigationCoordinator.isPlayerExpanded
    }

    var body: some Commands {
        CommandMenu(String(localized: "menu.playback")) {
            // Player visibility (existing)
            playerToggleButton

            Divider()

            // Core playback
            playPauseButton

            Divider()

            // Seeking
            seekBackward10Button
            seekForward10Button
            seekBackward30Button
            seekForward30Button

            Divider()

            // Navigation
            previousVideoButton
            nextVideoButton

            Divider()

            // Speed
            slowerButton
            fasterButton
            resetSpeedButton

            Divider()

            // Volume
            volumeUpButton
            volumeDownButton
            muteButton

            Divider()

            // Display modes
            pipButton
            
            Divider()
            closeVideoButton
        }
    }

    // MARK: - Player Visibility

    private var playerToggleButton: some View {
        Button {
            togglePlayerExpanded()
        } label: {
            Text(isPlayerExpanded
                ? String(localized: "menu.playback.hidePlayer")
                : String(localized: "menu.playback.showPlayer"))
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(!hasActiveVideo)
    }

    private func togglePlayerExpanded() {
        if isPlayerExpanded {
            navigationCoordinator.isPlayerExpanded = false
        } else {
            navigationCoordinator.expandPlayer()
        }
    }

    // MARK: - Core Playback

    private var playPauseButton: some View {
        Button {
            playerService.togglePlayPause()
        } label: {
            Text(String(localized: "menu.playback.playPause"))
        }
        .keyboardShortcut("k", modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    // MARK: - Seeking

    private var seekBackward10Button: some View {
        Button {
            playerService.seekBackward(by: 10)
        } label: {
            Text(String(localized: "menu.playback.seekBackward10"))
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private var seekForward10Button: some View {
        Button {
            playerService.seekForward(by: 10)
        } label: {
            Text(String(localized: "menu.playback.seekForward10"))
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private var seekBackward30Button: some View {
        Button {
            playerService.seekBackward(by: 30)
        } label: {
            Text(String(localized: "menu.playback.seekBackward30"))
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
        .disabled(!hasActiveVideo)
    }

    private var seekForward30Button: some View {
        Button {
            playerService.seekForward(by: 30)
        } label: {
            Text(String(localized: "menu.playback.seekForward30"))
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .disabled(!hasActiveVideo)
    }

    // MARK: - Navigation

    private var previousVideoButton: some View {
        Button {
            Task {
                await playerService.playPrevious()
            }
        } label: {
            Text(String(localized: "menu.playback.previousVideo"))
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        .disabled(!hasActiveVideo || !state.hasPrevious)
    }

    private var nextVideoButton: some View {
        Button {
            Task {
                await playerService.playNext()
            }
        } label: {
            Text(String(localized: "menu.playback.nextVideo"))
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        .disabled(!hasActiveVideo || !state.hasNext)
    }

    // MARK: - Speed

    private var slowerButton: some View {
        Button {
            cycleSpeedDown()
        } label: {
            Text(String(localized: "menu.playback.slower"))
        }
        .keyboardShortcut("[", modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private var fasterButton: some View {
        Button {
            cycleSpeedUp()
        } label: {
            Text(String(localized: "menu.playback.faster"))
        }
        .keyboardShortcut("]", modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private var resetSpeedButton: some View {
        Button {
            state.rate = .x1
            playerService.currentBackend?.rate = 1.0
        } label: {
            Text(String(localized: "menu.playback.resetSpeed"))
        }
        .keyboardShortcut("0", modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private func cycleSpeedDown() {
        let rates = PlaybackRate.allCases
        guard let currentIndex = rates.firstIndex(of: state.rate) else { return }
        if currentIndex > 0 {
            let newRate = rates[currentIndex - 1]
            state.rate = newRate
            playerService.currentBackend?.rate = Float(newRate.rawValue)
        }
    }

    private func cycleSpeedUp() {
        let rates = PlaybackRate.allCases
        guard let currentIndex = rates.firstIndex(of: state.rate) else { return }
        if currentIndex < rates.count - 1 {
            let newRate = rates[currentIndex + 1]
            state.rate = newRate
            playerService.currentBackend?.rate = Float(newRate.rawValue)
        }
    }

    // MARK: - Volume

    private var volumeUpButton: some View {
        Button {
            let newVolume = min(1.0, state.volume + 0.1)
            state.volume = newVolume
            playerService.currentBackend?.volume = newVolume
        } label: {
            Text(String(localized: "menu.playback.volumeUp"))
        }
        .keyboardShortcut(.upArrow, modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private var volumeDownButton: some View {
        Button {
            let newVolume = max(0.0, state.volume - 0.1)
            state.volume = newVolume
            playerService.currentBackend?.volume = newVolume
        } label: {
            Text(String(localized: "menu.playback.volumeDown"))
        }
        .keyboardShortcut(.downArrow, modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private var muteButton: some View {
        Button {
            state.isMuted.toggle()
            playerService.currentBackend?.isMuted = state.isMuted
        } label: {
            Text(String(localized: "menu.playback.mute"))
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(!hasActiveVideo)
    }

    // MARK: - Display Modes

    private var pipButton: some View {
        Button {
            if let mpvBackend = playerService.currentBackend as? MPVBackend {
                mpvBackend.togglePiP()
            }
        } label: {
            Text(String(localized: "menu.playback.pip"))
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(!hasActiveVideo || !state.isPiPPossible)
    }
    
    // MARK: - Close video button
    
    private var closeVideoButton: some View {
        Button {
            closeVideo()
        } label: {
            Text(String(localized: "menu.playback.closeVideo"))
        }
        .keyboardShortcut(".", modifiers: [.command])
        .disabled(!hasActiveVideo)
    }

    private func closeVideo() {
        // Mark as closing to hide tab accessory before dismissal
        state.isClosingVideo = true

        // Clear the queue when closing video
        appEnvironment.queueManager.clearQueue()

        // Reset panel state when closing player
        settingsManager.landscapeDetailsPanelVisible = false
        settingsManager.landscapeDetailsPanelPinned = false

        // Stop player FIRST before dismissing window
        playerService.stop()

        // Then dismiss player window (after backend is stopped)
        navigationCoordinator.isPlayerExpanded = false
    }
}
#endif
