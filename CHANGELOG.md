## What's Changed

### New Features

* Multiple accounts: sign in to several accounts on the same instance, switch between them from Home, the sidebar or the toolbar, rename them, and sync them to your other devices through iCloud; the switcher shows when an account needs attention and can be hidden outside Settings
* Subscriptions, feed, playlists and watch history now follow the selected account, and accounts can be set inactive without signing out
* Manage Invidious and Piped account playlists: create, rename, edit the description, delete, and add or remove videos; set privacy on Invidious
* Invidious watch history: videos you play are saved to the selected account's history on the server, and the History screen shows that history and can remove videos from it
* Choose where a subscription or playlist addition goes: Subscribe On in the channel menu and an account picker in Add to Playlist, covering local storage and every signed-in account
* Redesigned player details panel with pages (Info, Comments, Queue and more), configurable presets, per-page element customization, per-orientation visibility and section ordering
* New corner player layout on iPad and macOS, now the default for built-in presets
* iPhone Duo support: tabletop layout with the video above the hinge, split layout in book posture, sidebar on the inner screen, exterior display support and Foldable playback settings
* Shortcuts and Siri support, including voice commands for player controls and sections
* URL scheme actions (play, queue, download, bookmark, subscribe, player controls, open settings) with x-callback-url support; Yattee 1.x links work again
* Open Link handles more YouTube link types including playlists and @handle channels, opens a single link straight into its details and shows several links as mixed results
* Play direct media links without Yattee Server
* Hide Shorts toggle in view options
* Navigation setting to keep the tab bar on large screens
* Toolbar layout for video info actions with a configurable primary action; the macOS toolbar now shows every action
* Remote Servers and File Sources sections on Home
* Share videos via privacy frontend URLs, with an optional frontend URL for Piped instances
* Refresh, accounts and link actions in the instance browse menu
* Currently Playing toggle and empty-queue placeholder in the queue page
* Player notifications (toasts) for actions and errors
* Build date in About
* Keyboard shortcuts on iPad and macOS to toggle the corner layout panels (⌥⌘I info, ⌥⌘S side column, ⌥⌘P both)
* macOS: Copy Link in the video context menu (#972)

### Improvements

* Playlist Play starts at a random video in shuffle mode (#988)
* Comments are configured from their row in details panel settings
* Ask Play Now or Play Next when a video is still playing and the queue is empty
* Redesigned video info header with collapsible chapters and related videos sections; empty descriptions are hidden
* Video details load failures are now shown instead of a blank view
* Smooth video resizing during animations on iOS, such as corner layout panel toggles and rotation
* Volume and mute respond immediately with the AVFoundation audio output, now preferred on iOS and macOS
* Instance subscription imports let you choose where subscriptions go
* Playback prefers the active instance
* Downloaded media is excluded from iCloud backups
* Data is re-fetched from iCloud when the local store was recreated
* VoiceOver reads the title, channel and duration for video rows
* Basic auth credentials moved to the Security section when editing an instance
* Channel strip is used when the subscriptions column is too narrow
* Pinch to pan & scan in the tabletop and corner layouts
* macOS: Command-Enter opens links
* tvOS: Apple TV stays awake during audio-only playback, darker player with solid focused controls, link confirmations shown as alerts, Cancel offered while slow pages load

### Bug Fixes

* Fix a crash opening Search when a video is in history under several sources
* Fix the app being killed while saving playback progress during suspension
* Fix a crash rendering video after the app went to the background
* Fix a crash with SMB media sources when downloading and playing at the same time
* Fix Sync Now dropping unsent history, progress and bookmark changes (#978)
* Fix downloads failing until relaunch after toggling cellular downloads (#975)
* Fix the subscription feed not updating after subscribing or unsubscribing (#968)
* Fix Now Playing reporting playback as audio (#969)
* Fix being locked out of Settings on tvOS after hiding it from the sidebar (#986)
* Fix missing comment avatars with newer Invidious versions
* Fix player controls covered by the camera cutout on the iPhone Duo exterior display
* Fix the landscape panel opening on every rotation on the iPhone Duo exterior display
* Fix a crash when syncing watch history for videos with very long IDs
* Fix white text in video info with the light tvOS color scheme
* Fix macOS inline player aspect resizing and playback continuing after its window closes
* Fix macOS player window oscillating when resizing across the corner layout threshold
* Fix macOS Picture in Picture sizing and the PiP window staying open after closing the video
* Fix clipped top controls in corner layout fullscreen
* Fix video jumping when dismissing the portrait details panel
* Fix portrait panel tabs blocked by the drag handle
* Fix the player dismiss gesture starting from side sliders and the panel resize handle
* Fix landscape panel moving while Notification Center is open
* Fix video info thumbnails and cards misaligned after resizing or rotation
* Fix search field not activating when selecting the Search tab on iOS 27
* Fix tvOS focus lost after removing a Continue Watching entry
* Fix darker edges beside narrow pages like the empty Search on macOS
* Fix sheets staying open when opening a link from outside the app
* Fix Video Info and Go to Channel from rows inside the player not collapsing the player
