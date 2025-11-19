## Build 209

## What's Changed

* Fix Now Playing controls for both MPV and AVPlayer backends
* Fix thumbnail sizing and aspect ratio issues in video cells (#896)
* Adjust tvOS video cell dimensions for better layout
* Fix playing videos from channel view in modal opened in video player
* Fix audio track label showing "Original" instead of "Unknown"
* Simplify fullscreen handling for iOS
* Add macOS-specific entitlements for MPV backend

## Previous builds

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
