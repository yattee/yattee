

## What's Changed

### New Features

* Add embedded audio/subtitle track selection for multi-track files
* Add loading external subtitle files for media-source playback
* Add view options to playlists list view
* Add search to playlists list view
* Show and label WebDAV/SMB video streams in the quality selector

### Bug Fixes

* Fix timed links resuming at watch position instead of URL timestamp
* Fix autoplay countdown showing in repeat one queue mode
* Fix double-tap fullscreen gesture rotating on portrait videos
* Fix sending extracted videos (Twitch streams) to other devices
* Fix missing thumbnails for videos saved to library
* Fix #955: make subtitle appearance settings adjustable on tvOS
* Fix #960: scope subscription counts, import/export to active account
* Fix #958: switch MPVKit to yattee fork with AV1 VideoToolbox session recovery
* Fix startup crash in sideloaded builds without iCloud entitlements
* Allow screen sleep during audio-only playback
* Apply thumbnail fallback everywhere a single URL was rendered
* Stop tracking resume progress for live streams
* Label local-file video quality from mpv track info instead of Unknown
* Keep macOS player fullscreen when queue advances to different-aspect video
* Guard PiP bridge geometry writes against non-finite rects
