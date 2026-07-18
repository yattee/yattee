## What's Changed

**macOS support** — Yattee 2 arrives on the Mac with its first public beta. It brings the full Yattee 2 experience to the desktop with a native interface: a dedicated player window with fullscreen and stay on top option, Picture in Picture, customizable and movable player controls, keyboard shortcuts, and other features present in the iOS app.

The macOS app is available via [TestFlight](https://yattee.stream/beta2), or as a notarized direct download from [GitHub Releases](https://github.com/yattee/yattee/releases) that keeps itself up to date with built-in automatic updates.

### General

#### New Features

* Add audio-only music mode, available in video player settings and player controls button
* Add custom accent color setting with system color picker and separate light and dark mode colors
* Redesign Home shortcut cards with layout, color, and palette options and a live style preview
* Add Edit Shortcuts and Hide options to Home shortcut context menus
* Add pause, resume, and cancel context menu to download rows
* Add manual legacy account import and allow importing account-less legacy instances as sources

#### Improvements

* Rework iCloud sync engine for more reliable syncing; resume sync from saved state instead of re-fetching everything
* Sync watch progress when a video plays to the end and when the app goes to the background
* Fall back to lower-quality thumbnails when higher-resolution variants are unavailable
* Apply the selected theme at the window level so it takes effect everywhere

#### Bug Fixes

* Fix disabling Background Playback having no effect
* Fix downloads never finishing and a crash on download completion
* Fix missing storyboards when advancing to the next queued video
* Fix live videos shown in the mini player bar
* Fix crash when opening the share sheet on iPad
* Fix rare data loss when the app is suspended in the background
* Fix iCloud sync conflicts for recent channels, playlists, and watch progress
* Fix Sources home shortcut counting disabled instances

### iOS

* Use toolbar search placement on iPad channel view

### tvOS

* Add A/V sync diagnostics settings page
* Default Channels grid to 5 columns
* Fixes for some reported playback issues
