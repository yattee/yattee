## Build 140
* Improved player layout
  - Video titles can now span multiple lines for readability
  - Channel details and video dates/likes/dislikes displayed below title
  - Segmented picker between Info page and Comments
  - Info page combines description, chapters, inspector, and related
  - Description is collapsed by default, tap to expand
  - Chapters are displayed in horizontal scroll view
  - Gesture to toggle fullscreen size of details is changed to double tap above action buttons
* Opening channel from current video, related or from comments will open it in sheet above player instead of in browser (iOS)
* Added settings toggles for enabling more action buttons:
  - Toggle fullscreen
  - Toggle PiP
  - Lock orientation
  - Restart video
  - Play next video
  - Music mode
* Added browsing setting to toggle visibility of button to change video watch status
* Added player setting to show Inspector always or only for local videos
* Added player setting to show video descriptions expanded (now gets collapsed by default)
* Added playback mode menu to Playback Settings
* Changed layout to vertical and added configuration buttons for remaining views on tvOS (Popular, Trending, Playlists, Search)
* Simplified animation on closing player
* Removed "Watch Next" view
* Fixed reported crashes
* Fixed issues with opening channel URLs
* Fixed issue where account username would get truncated
* Fixed issue where marking all feed videos as watched/unwatched would not refresh actions in Subscriptions menu
* Fixed issue where closing channel would require multiple back presses
* Other minor changes and improvements

### Previous Builds
* Added pagination/infinite scroll for channel contents (Invidious and Piped)
* Added support for channel tabs for Invidious (previously available only for Piped)
* Added filter to hide Short videos, available via view menu/toolbar button
* Added localizations: Arabic, Japanese, Portugese, Portuguese (Brazil)
* Added browsing setting: "Show unwatched feed badges"
* Fixed reported crashes
* Fixed issue where channels in Favorites would not refresh contents
* Other minor changes and improvements
