## What's Changed

### New Features
* Persist media browser view options per source
* Add Enable All / Disable All menu to channel notifications settings
* Add context menu and swipe actions to related videos in Video Info View
* Persist author cache to disk for instant channel info across restarts

### Improvements
* Change default player layout settings
* Show video thumbnail in mini player during PiP
* Update media browser view options sheet layout
* Move close video button from toolbar into now playing card in Remote Control

### Bug Fixes
* Fix deleted playlists resurrecting from iCloud after app restart
* Fix feed channel filter avatars showing placeholders instead of images
* Fix Invidious login failing for passwords with special characters
* Fix subscriber count layout shift in Video Info View channel row
* Fix Feed tab flashing Content Unavailable View on initial load
* Fix blurred background gradient not using DeArrow thumbnail
* Fix playlist rows in Channel View not tappable in empty space
* Fix lock screen always showing 10s seek regardless of system controls setting
* Fix player dismiss gesture stuck after panel dismiss with comments expanded
* Fix incomplete playlist loading by paginating through all pages
* Fix pull-to-refresh scroll offset not resetting in Instance Browse View
* Fix URL scheme UI tests for YouTube deep links and content loading
* Fix UI tests for onboarding flow and AddRemoteServer redesign
* Fix panscan zoom pushing controls off screen for portrait videos

### Development
* Add Fastlane config and update release workflow for v2
* Add DEV badge on iCloud settings for debug builds
* Add git-cliff based changelog generator
* Add AltStore source and separate update workflow from release pipeline
* Add URL scheme UI tests for deep link navigation
* Refactor views
