## What's Changed

### General

#### New Features

* Add Allow Software-Decoded Formats playback setting
* Add Show Sidebar toggle to Subscriptions view options
* Render clickable links and timestamps in comment text
* Route YouTube links tapped in descriptions through in-app playback
* Resolve URL shorteners and prompt for ambiguous description links
* Rename YouTube Enhancements settings to Integrations and move above Advanced
* Show watch progress bar on thumbnails in playlist, channel, and search views

#### Bug Fixes

* Resume and seek when reopening the currently-loaded video
* Refresh track list when advancing to the next queued video
* Suppress stale player error after switching videos mid-retry
* Surface mpv error details on stream load failure
* Fix local folder playback after app container UUID changes
* Skip local-folder watches from iCloud sync

#### Sources & Backends

* Surface clearer error when adding a Piped frontend URL
* Send Piped session token in the Authorization header again
* Block HTTP Basic Auth proxy for Piped sources
* Cache and prewarm Invidious proxy auto-detection
* Route Yattee Server playback through `/proxy/relay` when "Proxy Videos" is on

#### Improvements

* Prefetch fresh video thumbnail before swapping it into the info view
* Stabilize thumbnail cache across rotating URL tokens to avoid reloads
* Tweak Subscriptions view options sheet layout

### iOS

* Add channels sidebar to Subscriptions on iPad
* Round player seek bar and show the scrubber only while dragging
* Add interactive swipe-to-dismiss for toasts

### tvOS

#### New Features

* Add press-and-hold continuous seek on the d-pad
* Expose Background Playback toggle (default off)
* Add Show Sidebar toggle to the Subscriptions view
* Add display frame rate and dynamic range matching
* Show cached channel header while the channel loads
* Live-seek the scrubber and auto-commit on idle; pause playback on entering scrub mode
* Keep player controls visible on pause via an on-screen button
* Show playback failure overlay; dismiss player panels when playback fails

#### Bug Fixes

* Fix MPV startup playback stability
* Fix MPV Options focus and Add/Edit sheet layout
* Fix pickers
* Fix soft-lock in import views when no rows are focusable
* Unstick focus dead-ends in channel views
* Make detail dismiss button opt-in and unstick more views
* Dismiss sidebar detail pages when sidebar selection changes
* Suppress Now Playing while an AirPlay/HomePod route is active
* Hide feed channel filter strip
* Enforce minimum 2 grid columns
* Prevent focus shadow from clipping between Home sections

#### Improvements

* Convert settings and queue to half-screen panels; constrain details panel to the right half
* Make the watched checkmark more prominent on thumbnails
* Use light glass background for player control buttons; black icons on focused buttons for legibility
* Match play button background to prev/next transport buttons
* Remove the close button from the MPV debug stats overlay
* Present instance login as a full-screen cover
