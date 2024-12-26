## Build 198

## What's Changed
* Stop making videos with unknown length shorts. by @derspyy in https://github.com/yattee/yattee/pull/849
* Translations update from Hosted Weblate by @weblate in https://github.com/yattee/yattee/pull/845
* Add Hungarian to locales list
* Update dependencies

## Previous builds
* Add skip, play/pause, and fullscreen shortcuts to macOS player (by @rickykresslein)
* Added Settings Import/Export
  * Export all settings, instances and accounts
  * Import selected elements from the file
  * Include unencrypted passwords in the export or provide them during the import
  * Import via URL for tvOS
* Added Controls setting "Action button labels" icon or icon and text
* Added Advanced setting for MPV: "deinterlace"
* Add help text to all header buttons (by @rickykresslein)
* History Setting: hide the recent activity in the sidebar or limit the number of items shown (by @rickykresslein)
* Fix issues with empty comments (by @stonerl)
* Improved Invidious comments (by @stonerl)
* Allow import of accounts to manually added (not imported) instances
* Add import export of missing settings
* macOS: Fix settings windows layout
* Fix seek OSD layout on tvOS, revert OSD position
* Allow users to disable fullscreen swipe gesture by @stonerl in https://github.com/yattee/yattee/pull/814
* Proper audio interrupt and route change handling by @stonerl in https://github.com/yattee/yattee/pull/815
* Improved subtitle handling by @stonerl in https://github.com/yattee/yattee/pull/817
* Improvements to MPVGLView by @stonerl in https://github.com/yattee/yattee/pull/818
* Add drag gestures to video details by @stonerl in https://github.com/yattee/yattee/pull/820
* Fix uneven playback when using MPV and not syncing refreshrate by @blennster in https://github.com/yattee/yattee/pull/833
* Norwegian Language by @mmaalo in https://github.com/yattee/yattee/pull/834
* Translations update from Hosted Weblate by @weblate in https://github.com/yattee/yattee/pull/836
* Update MPVKit to v0.39.0 by @stonerl in https://github.com/yattee/yattee/pull/824
* Update SwiftUI-Introspect by @stonerl in https://github.com/yattee/yattee/pull/813
* Orientation/Fullscreen fixes and cleanup by @stonerl in https://github.com/yattee/yattee/pull/806
* More robust resolution handling by @stonerl in https://github.com/yattee/yattee/pull/807
* MPV: improved A/V sync by @stonerl in https://github.com/yattee/yattee/pull/805
* Retry loading video before presenting error by @stonerl in https://github.com/yattee/yattee/pull/810
* Refactor Search by @stonerl in https://github.com/yattee/yattee/pull/809
* iOS: Simplified fullscreen and orientation by @stonerl in https://github.com/yattee/yattee/pull/786
* macOS: only apply player shortcuts when window is active by @stonerl in https://github.com/yattee/yattee/pull/802
* player controls: add background opacity selection by @stonerl in https://github.com/yattee/yattee/pull/799
* add missing Shorts resolutions by @stonerl in https://github.com/yattee/yattee/pull/797
* use -O1 on macOS by @stonerl in https://github.com/yattee/yattee/pull/801
* Gestures: swipe up toggles fullscreen by @stonerl in https://github.com/yattee/yattee/pull/778
* don’t open video when dismissing context menu by @stonerl in https://github.com/yattee/yattee/pull/780
* mpv: remove video layer when entering background by @stonerl in https://github.com/yattee/yattee/pull/793
* hi-res invidious logos by @stonerl in https://github.com/yattee/yattee/pull/791
* enable -O3 by @stonerl in https://github.com/yattee/yattee/pull/794
* Better audio ducking by @stonerl in https://github.com/yattee/yattee/pull/779
* fix picture in picture by @stonerl in https://github.com/yattee/yattee/pull/789
* Invidious: propper HTTP basic auth support by @stonerl in https://github.com/yattee/yattee/pull/762
* Apply correct orientation by @stonerl in https://github.com/yattee/yattee/pull/770
* Circular Invidious logo by @stonerl in https://github.com/yattee/yattee/pull/769
* Video Thumbnails: retry 3 times fetching from URL by @stonerl in https://github.com/yattee/yattee/pull/768
* Make thumbnail fill the view in music mode by @stonerl in https://github.com/yattee/yattee/pull/766
* Changes to defaults by @stonerl in https://github.com/yattee/yattee/pull/767
* Fixed fullscreen handling for backgrounding by @stonerl in https://github.com/yattee/yattee/pull/772
* Update now playing info when using system controls – Partial fix for 503 by @stonerl in https://github.com/yattee/yattee/pull/765
* Fix crash on HLS live playback by @stonerl in https://github.com/yattee/yattee/pull/775
* Fix mpv crashing on macOS by @stonerl in https://github.com/yattee/yattee/pull/754
* Refreshed icons for iOS and macOS by @stonerl in https://github.com/yattee/yattee/pull/752
* Add new MPVKit repo by @stonerl in https://github.com/yattee/yattee/pull/753
* Add Chinese (Simplified) - zh-Hans to LanguageCodes by @stonerl in https://github.com/yattee/yattee/pull/757
* Color changes to VideoActions by @stonerl in https://github.com/yattee/yattee/pull/759
* Hide VideoActions Bar when no buttons is visible by @stonerl in https://github.com/yattee/yattee/pull/760
* Improved stream resolution handling by @stonerl in https://github.com/yattee/yattee/pull/747
* Fix some potential crashes by @stonerl in https://github.com/yattee/yattee/pull/748
* Fix regression and improve curentChapter handling by @stonerl in https://github.com/yattee/yattee/pull/749
* Refined chapter font scaling by @stonerl in https://github.com/yattee/yattee/pull/750
* Improved thumbnail handling  by @stonerl in https://github.com/yattee/yattee/pull/740
* iOS: make timestamps in comments touchable by @stonerl in https://github.com/yattee/yattee/pull/741
* Improvements to opening channels from Videos by @stonerl in https://github.com/yattee/yattee/pull/742
* Allow hiding comments by @stonerl in https://github.com/yattee/yattee/pull/744
* Add option to exit fullscreen on end by @stonerl in https://github.com/yattee/yattee/pull/570
* Only updateWatch status while video is playing by @stonerl in https://github.com/yattee/yattee/pull/745
* Xcode 16 - update recommended settings by @stonerl in https://github.com/yattee/yattee/pull/737
* Translations update from Hosted Weblate by @weblate in https://github.com/yattee/yattee/pull/724
* tvOS: Allow account picker by long pressing channels button in subscriptions view by @patelhiren in https://github.com/yattee/yattee/pull/704
* tvOS: Refined Subscriptions View by @patelhiren in https://github.com/yattee/yattee/pull/697
* More responsive UI when Favorites are used. by @stonerl in https://github.com/yattee/yattee/pull/695
* Improved conditional proxying by @stonerl in https://github.com/yattee/yattee/pull/696
* Don't show related in sidebar when disabled in settings by @stonerl in https://github.com/yattee/yattee/pull/635
* Handle audio session interrupts by other media by @stonerl in https://github.com/yattee/yattee/pull/640
* Only show Queue header in sidebar view by @stonerl in https://github.com/yattee/yattee/pull/642
* SponsorBlock Improvements by @stonerl in https://github.com/yattee/yattee/pull/639
* Chapter title on jump by @stonerl in https://github.com/yattee/yattee/pull/655
* Restart finished video by @stonerl in https://github.com/yattee/yattee/pull/646
* SponsorBlock jump to end instead of pausing by @stonerl in https://github.com/yattee/yattee/pull/648
* Call correct class of  SDImageAWebPCoder by @stonerl in https://github.com/yattee/yattee/pull/664
* Fix handling and displaying captions by @stonerl in https://github.com/yattee/yattee/pull/636
* Advanced settings: make number fields .numPad by @stonerl in https://github.com/yattee/yattee/pull/661
* Preserve time on stream change by @stonerl in https://github.com/yattee/yattee/pull/651
* Switch to previous backend when leaving PiP by @stonerl in https://github.com/yattee/yattee/pull/641
* Handle deep links by @timonus in https://github.com/yattee/yattee/pull/645
* Music Mode: don't bindPlayerToLayer when entering foreground by @stonerl in https://github.com/yattee/yattee/pull/644
* Allow user to disable thumbnails and jump to current chapter in horizontal view by @stonerl in https://github.com/yattee/yattee/pull/665
* Rework qualitiy settings by @stonerl in https://github.com/yattee/yattee/pull/650
* HLS: set target bitrate / AVPlayer: higher resolution by @stonerl in https://github.com/yattee/yattee/pull/667
* Fix #619: Remove ports from shared YouTube links by @0x000C in https://github.com/yattee/yattee/pull/627
* XCode enable IDEPreferLogStreaming by @stonerl in https://github.com/yattee/yattee/pull/638
* Conditional proxying by @stonerl in https://github.com/yattee/yattee/pull/662
* HomeView: Changes to Favourites and History Widget by @stonerl in https://github.com/yattee/yattee/pull/672
* Snappy UI - Offloading non UI task to background threads by @stonerl in https://github.com/yattee/yattee/pull/671
* Fix PiP Mode Not Working Using MPV by @stonerl in https://github.com/yattee/yattee/pull/676
* Fix thumbnails failing to load on tvOS by @patelhiren in https://github.com/yattee/yattee/pull/688
* speed up sorting for Stream by @stonerl in https://github.com/yattee/yattee/pull/681
* faster chapter extraction by @stonerl in https://github.com/yattee/yattee/pull/682
* Invidious: add images to chapters by @stonerl in https://github.com/yattee/yattee/pull/685
* Improved Captions handling by @stonerl in https://github.com/yattee/yattee/pull/684
* Add User-Agent to request by @stonerl in https://github.com/yattee/yattee/pull/680
* MPV: speed up playback start by @stonerl in https://github.com/yattee/yattee/pull/689
* Advanced Settings: cache-pause-initial by @stonerl in https://github.com/yattee/yattee/pull/679
* Changed description for Format reordering by @stonerl in https://github.com/yattee/yattee/pull/677
* Add Chinese (Traditional) localization (by @rexcsk)
* Localization fixes
* Updated localizations
* Upgraded dependencies
* Fixed reported crash
* Other minor changes and improvements

**Big thanks to the current, past and future project contributors!**
