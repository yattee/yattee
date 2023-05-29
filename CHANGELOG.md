## Build 152
* Tapping second time on search tab button focuses the input field and selects entered query text (iOS)
* Added Browsing setting "Keep channels with unwatched videos on top of subscriptions list"
* Improved buttons and layout on tvOS
* Fixed issue with trending categories (Invidious) not working when using non-English language
* Fixed issue with search query suggestions not being displayed properly in some languages
* Changed subscriptions page picker label from icon to text
* Views will display information if there is no videos to show instead of always showing placeholders
* Fixed AVPlayer issue with music mode playing video track
* Added remove context menu option for all types of recent items in Search
* Added advanced setting "Show video context menu options to force selected backend"
* Fixed reported crashes
* Other minor fixes and improvements

## Previous Builds
* Improved Home
  - Added menu with view options on iOS and toolbar buttons on macOS/tvOS
  - Added Home Settings
  - Moved settings from Browsing to Home Settings
  - Enhanced Favorites management: select listing type and videos limit for each element
  - Select listing type for History just like for Favorites
* Added view option to hide watched videos
* Added Browsing setting "Startup section"
* Added feed/channels list segmented picker in Subscriptions and moved view options menu on iOS
* Thumbnails in list view respect "Round corners" setting
* Added watching progress indicator to list view
* Moved "Show toggle watch status button" to History settings
* Removed "Rotate to portrait when exiting fullscreen" setting - it is instead automatically decided depending on device type
* Fixed channels view layout on tvOS
* Fixed channels and playlists navigation on tvOS
* Fixed issue where controls were not visible when music mode was enabled
* Fixed issue with closing Picture in Picture on macOS
* Fixed issue where playing video with AVPlayer would cause it to be immediately marked as watched
* Fixed issue with playlists view showing duplicated buttons when "Show cache status" is enabled
* Fixed issue where navigating to channel from list view in Playlists and Search would immediately go back
* Fixed issue where first URL would fail to open

* Added support for AVPlayer native system controls on iOS and macOS
  - Use system features such as AirPlay, subtitles switching (Piped with HLS), text detection and copy and more
  - Added Controls setting: "Use system controls with AVPlayer"
* Player rotates for landscape videos on entering full screen on iOS
  - Player > Orientation setting: "Rotate when entering fullscreen on landscape video"
* Added Player > Playback setting: "Close video and player on end"
* Added reporting for opening stream in OSD for AVPlayer
* Fixed issue with opening channels and playlists links
* Fixed issues where controls/player layout could break (e.g., when going to background and back)
* Fixed issue where stream picker would show duplicate entries
* Fixed issue where search suggestions would show unnecessary bottom padding
* Fixed landscape channel sheet layout in player
* Fixed reported crashes
* Localization updates and fixes
* Other minor fixes and improvements
