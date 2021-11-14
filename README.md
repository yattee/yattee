![Yattee Banner](https://r.yattee.stream/icons/yattee-banner.png)

Video player with support for [Invidious](https://github.com/iv-org/invidious) and [Piped](https://github.com/TeamPiped/Piped) instances built for iOS 15, tvOS 15 and macOS Monterey.


![Screenshot](https://r.yattee.stream/screenshots/all-platforms.png)

## Features
* Native user interface built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
* Multiple instances and accounts, fast switching
* [SponsorBlock](https://sponsor.ajay.app/) with selection of categories to skip
* Player queue and history
* Fullscreen playback and Picture in Picture
* Stream quality selection
* Favorites: customizable section of channels, playlists, trending, searches and other views
* AirPlay support
* Safari Extension for macOS and iOS for redirecting to the app
* URL Scheme for easy integrations

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

## Installation
### Requirements
Application is built using latest APIs, that's why for now **only recent** software versions: iOS/tvOS 15 or macOS Monterey are supported.

### How to install?
#### [AltStore](https://altstore.io/)
You can sideload IPA files that you can download from Releases page.
Alternatively, if you have to access to the beta AltStore version (v1.5), you can add the following repository in `Browse > Sources` screen: `https://alt.yattee.stream`

#### Manual installation
Download sources and compile them on a Mac using Xcode, install to your devices. Please note that if you are not registered in Apple Developer Program then the applications will require reinstalling every 7 days.

## Integrations
### Safari
macOS and iOS apps include Safari extension which will redirect opened YouTube tabs to the app.
### Firefox
You can use [Privacy Redirect](https://github.com/SimonBrazell/privacy-redirect) extension to make the videos open in the app. In extension settings put the following URL as Invidious instance: `https://r.yatte.stream`

### macOS
With [Finicky](https://github.com/johnste/finicky) you can configure your systems so the video links across the entire system will get opened in the app. Example configuration:
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
* [tvOS] To open settings press Play/Pause button while hovering over navigation menu or video
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

## Contributing
Every contribution to make this tool better is very welcome. Start with [creating issue](https://github.com/yattee/app/issues/new) to have discussion which can be later transformed into a Pull Request.

Review existing Issues and Pull Requests before creating new ones.

## License and Liability

Yattee and its components is shared on [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.en.html) license.

Contributors take no responsibility for the use of the tool (Point 16. of the license). We strongly recommend you abide by the valid official regulations in your country. Furthermore, we refuse liability for any inappropriate use of the tool, such as downloading materials without proper consent.

This tool is an open source software built for learning and research purposes.
