![Yattee Banner](https://r.yattee.stream/icons/yattee-banner.png)

Video player for [Invidious](https://github.com/iv-org/invidious) and [Piped](https://github.com/TeamPiped/Piped) instances built for iOS, tvOS and macOS.


[![AGPL v3](https://shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.en.html)
[![GitHub issues](https://img.shields.io/github/issues/yattee/yattee)](https://github.com/yattee/yattee/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/yattee/yattee)](https://github.com/yattee/yattee/pulls)
[![Matrix](https://img.shields.io/matrix/yattee:matrix.org)](https://matrix.to/#/#yattee:matrix.org)


![Screenshot](https://r.yattee.stream/screenshots/all-platforms.png)

## Features
* Native user interface built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
* Multiple instances and accounts, fast switching
* [SponsorBlock](https://sponsor.ajay.app/), configurable categories to skip
* Player queue and history
* Fullscreen playback, Picture in Picture and AirPlay support
* Stream quality selection
* Favorites: customizable section of channels, playlists, trending, searches and other views
* `yattee://` URL Scheme for integrations

### Availability
| Feature  | Invidious | Piped |
| - | - | - |
| User Accounts | ✅ | ✅ |
| Subscriptions | ✅ | ✅ |
| Popular | ✅ | 🔴 |
| User Playlists | ✅ | 🔴 |
| Trending | ✅ | ✅ |
| Channels | ✅ | ✅ |
| Channel Playlists | ✅ | ✅ |
| Search | ✅ | ✅ |
| Search Suggestions | ✅ | ✅ |
| Search Filters | ✅ | 🔴 |
| Subtitles | 🔴 | ✅ |
| Comments | 🔴 | ✅ |

## Installation
### Requirements
System requirements:
* iOS 14 (or newer)
* tvOS 15 (or newer)
* macOS Big Sur (or newer)

### How to install?

#### macOS
Download and run latest version from the [Releases](https://github.com/yattee/yattee/releases) page.

#### iOS/tvOS: [AltStore](https://altstore.io/) (free)
You can sideload IPA files downloaded from the [Releases](https://github.com/yattee/yattee/releases) page to your iOS or tvOS device - check [AltStore FAQ](https://altstore.io/faq/) for more information.

If you have to access to the beta AltStore version (v1.5, for Patreons only), you can add the following repository in `Browse > Sources` screen:

`https://alt.yattee.stream`

#### iOS/tvOS: Signing IPA files online (paid)
[UDID Registrations](https://www.udidregistrations.com/) provides services to sign IPA files for your devices. Refer to: ***Break free from the App Store*** section of the website for more information.

#### iOS/tvOS: Manual installation
Download sources and compile them on a Mac using Xcode, install to your devices. Please note that if you are not registered in Apple Developer Program you will need to reinstall every 7 days.

## Integrations
### macOS
With [Finicky](https://github.com/johnste/finicky) you can configure your system to open all the video links in the app. Example configuration:
```js
{
  match: [
    finicky.matchDomains(/(.*\.)?youtube.com/),
    finicky.matchDomains(/(.*\.)?youtu.be/)
  ],
  browser: "/Applications/Yattee.app"
}
```

## Screenshots
### iOS
| Player | Search | Playlists |
| - | - | - |
| [![Yattee Player iOS](https://r.yattee.stream/screenshots/iOS/player-thumb.png)](https://r.yattee.stream/screenshots/iOS/player.png) | [![Yattee Search iOS](https://r.yattee.stream/screenshots/iOS/search-suggestions-thumb.png)](https://r.yattee.stream/screenshots/iOS/search-suggestions.png) |  [![Yattee Subscriptions iOS](https://r.yattee.stream/screenshots/iOS/playlists-thumb.png)](https://r.yattee.stream/screenshots/iOS/playlists.png) |
### iPadOS
| Settings | Player | Subscriptions |
| - | - | - |
| [![Yattee Player iPadOS](https://r.yattee.stream/screenshots/iPadOS/settings-thumb.png)](https://r.yattee.stream/screenshots/iPadOS/settings.png) | [![Yattee Player iPadOS](https://r.yattee.stream/screenshots/iPadOS/player-thumb.png)](https://r.yattee.stream/screenshots/iPadOS/player.png) | [![Yattee Subscriptions iPad S](https://r.yattee.stream/screenshots/iPadOS/subscriptions-thumb.png)](https://r.yattee.stream/screenshots/iPadOS/subscriptions.png) |
### tvOS
| Player | Popular | Search | Now Playing | Settings |
| - | - | - | - | - |
| [![Yattee Player tvOS](https://r.yattee.stream/screenshots/tvOS/player-thumb.png)](https://r.yattee.stream/screenshots/tvOS/player.png) | [![Yattee Popular tvOS](https://r.yattee.stream/screenshots/tvOS/popular-thumb.png)](https://r.yattee.stream/screenshots/tvOS/popular.png) | [![Yattee Search tvOS](https://r.yattee.stream/screenshots/tvOS/search-thumb.png)](https://r.yattee.stream/screenshots/tvOS/search.png) | [![Yattee Now Playing tvOS](https://r.yattee.stream/screenshots/tvOS/now-playing-thumb.png)](https://r.yattee.stream/screenshots/tvOS/now-playing.png) | [![Yattee Settings tvOS](https://r.yattee.stream/screenshots/tvOS/settings-thumb.png)](https://r.yattee.stream/screenshots/tvOS/settings.png) |
### macOS
| Player | Channel | Search | Settings |
| - | - | - | - |
| [![Yattee Player macOS](https://r.yattee.stream/screenshots/macOS/player-thumb.png)](https://r.yattee.stream/screenshots/macOS/player.png) | [![Yattee Channel macOS](https://r.yattee.stream/screenshots/macOS/channel-thumb.png)](https://r.yattee.stream/screenshots/macOS/channel.png) | [![Yattee Search macOS](https://r.yattee.stream/screenshots/macOS/search-thumb.png)](https://r.yattee.stream/screenshots/macOS/search.png) | [![Yattee Settings macOS](https://r.yattee.stream/screenshots/macOS/settings-thumb.png)](https://r.yattee.stream/screenshots/macOS/settings.png) |

## Tips
### Settings
* [tvOS] To open settings, press Play/Pause button while hovering over navigation menu or video
### Navigation
* Use videos context menus to add to queue, open or subscribe channel and add to playlist
* [tvOS] Pressing buttons in the app trigger switch to next available option (for example: next account in Settings). If you want to access list of all options, press and hold to open the context menu.
* [iOS] Swipe the player/title bar: up to open fullscreen details view, bottom to close fullscreen details or hide player
### Favorites
* Add more sections using ❤️ button in views channels, playlists, searches, subscriptions and popular
* [iOS/macOS] Reorganize with dragging and dropping
* [iOS/macOS] Remove section with right click/press and hold on section name
* [tvOS] Reorganize and remove from `Settings > Edit Favorites...`
### Keyboard shortcuts
* `Command+1` - Favorites
* `Command+2` - Subscriptions
* `Command+3` - Popular
* `Command+4` - Trending
* `Command+F` - Search
* `Command+P` - Play/Pause
* `Command+S` - Play Next
* `Command+O` - Toggle Player


## Donations

You can support development of this app with
[Patreon](https://www.patreon.com/arekf) or cryptocurrencies:

**Monero (XMR)**
```
48zfKjLmnXs21PinU2ucMiUPwhiKt5d7WJKiy3ACVS28BKqSn52c1TX8L337oESHJ5TZCyGkozjfWZG11h6C46mN9n4NPrD
```
**Bitcoin (BTC)**
```
bc1qe24zz5a5hm0trc7glwckz93py274eycxzju3mv
```
**Ethereum (ETH)**
```
0xa2f81A58Ec5E550132F03615c8d91954A4E37423
```

Donations will be used to cover development program access and domain renewal costs.

## Contributing
If you're interestred in contributing, you can browse the [issues](https://github.com/yattee/yattee/issues) list or create a new one to discuss your feature idea. Every contribution is very welcome.

## License and Liability

Yattee and its components is shared on [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.en.html) license.

Contributors take no responsibility for the use of the tool (Point 16. of the license). We strongly recommend you abide by the valid official regulations in your country. Furthermore, we refuse liability for any inappropriate use of the tool, such as downloading materials without proper consent.

This tool is an open source software built for learning and research purposes.
