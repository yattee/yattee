## Build 211

## What's Changed

### iOS Fixes
* Fix menu text disappearing in navigation headers and playback settings
* Fix fullscreen gesture collision with notification center by adding 60pt safe zone at top
* Fix comments scrolling issue - comments at bottom of video details view are now fully accessible
* Restrict orientation locking to iPhone only (hide on iPad)

### tvOS Fixes
* Improve controls overlay with single-press menus for quality, stream, captions, and audio track selection
* Fix controls overlay button text legibility
* Fix captions list always showing as unavailable in MPV

### API & Backend Fixes
* Fix Invidious search API parameters (sort_by→sort, upload_date→date, view_count→views)
* Fix Invidious captions URL when companion is enabled
* Fix YouTube share links incorrectly including port from Invidious instance

### UI & Layout
* Fix home view empty sections taking excessive vertical space

### Advanced Settings
* Add experimental setting to hide videos without duration in Invidious instance settings (can be used to filter shorts)
* Add optional AVPlayer support for non-streamable MP4/AVC1 formats in advanced settings with warnings about slow loading

### Dependencies
* Update dependencies

## Previous builds

## Build 210

## What's Changed

* Trending and Hide Shorts was disabled due to changes in the video apps API
* Fix iPad iOS 18 keyboard dismissal issue in search
* Fix audio session interrupting other apps on launch
* Fix thumbnail loading for video details
* Fix thumbnail aspect ratio to prevent stretching and layout jumps
* Fix keyboard shortcut conflict for Show Player command

## Previous builds

**Build 209:**
* Fix Now Playing controls for both MPV and AVPlayer backends
* Fix thumbnail sizing and aspect ratio issues in video cells (#896)
* Adjust tvOS video cell dimensions for better layout
* Fix playing videos from channel view in modal opened in video player
* Fix audio track label showing "Original" instead of "Unknown"
* Simplify fullscreen handling for iOS
* Add macOS-specific entitlements for MPV backend

**Build 208:**
* Enable resizable windows on iPad
* Improve iPad UI behavior and settings layout
* Fix horizontal content extending behind sidebar on iPad
* Add proper padding to player controls and video details in non-fullscreen iPad windows
* Hide orientation lock controls on iPad (not applicable for iPad)
* Fix video player overlay to respect window fullscreen state
* Allow video player to extend into safe areas
* Fix iOS Now Playing Info Center integration for AVPlayer backend
* Fix button styling and safe area handling
* Fix picker label visibility in settings
* Improve video layer rendering
* Add macOS 26 compatibility for search UI
* Improve playback settings UI controls
* Add retry mechanism for file load errors (both MPV and AVPlayer)
* Fix MPV player vertical positioning in fullscreen mode
* Improve player controls visibility and layout
* Add nil safety checks for stream resolution and playback time handling
* Refactor dirty region handling in MPV video rendering
* Remove verbose logging from MPV rendering
* Improve layout stability and reduce unwanted animations
* Simplify stream description by removing instance info
* Update default visible sections from trending to popular
* Update MPVKit dependency
* Update Ruby dependencies
* Fix SwiftLint and SwiftFormat violations
* Fix main actor isolation warnings
* Update GitHub Actions to latest macOS and Xcode versions
