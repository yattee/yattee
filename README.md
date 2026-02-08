<div align="center">
  <!-- TODO: new logo asset -->
  <img src="https://r.yattee.stream/icons/yattee-150.png" width="150" height="150" alt="Yattee logo">
  <h1>Yattee</h1>
  <p>Privacy-focused video player for iOS, macOS, and tvOS</p>

[![AGPL v3](https://shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.en.html)
[![GitHub issues](https://img.shields.io/github/issues/yattee/yattee)](https://github.com/yattee/yattee/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/yattee/yattee)](https://github.com/yattee/yattee/pulls)
[![Matrix](https://img.shields.io/matrix/yattee:matrix.org)](https://matrix.to/#/#Yattee:matrix.org)

[![Discord](https://invidget.switchblade.xyz/pSnNKhZHEG)](https://yattee.stream/discord)

<!-- TODO: new screenshot assets -->
![Screenshot](https://r.yattee.stream/screenshots/all-platforms.png)
</div>

## Features

**Playback**
- 4K video with custom MPV-based player
- Picture in Picture, background audio, fullscreen
- Playback queue, history, resume from last position
- Chapter navigation, playback speed, subtitles and captions
- Gesture controls (seek, volume, brightness)

**Content Sources**
- YouTube via Invidious, Piped, or self-hosted Yattee Server
- PeerTube instances (federated video)
- Local files, SMB network shares, WebDAV servers

**Integrations**
- [SponsorBlock](https://sponsor.ajay.app/) (configurable skip categories)
- [DeArrow](https://dearrow.ajay.app/) (crowdsourced titles and thumbnails)
- [Return YouTube Dislike](https://returnyoutubedislike.com/)

**Privacy**
- No tracking, no ads, no account required
- All traffic goes through your chosen instances

**Library**
- Subscriptions with per-channel notifications
- Bookmarks, playlists, watch history
- Search across all configured sources
- Import/export subscriptions (JSON, CSV, OPML)

**Downloads & Sync**
- Offline video and audio downloads
- iCloud sync for bookmarks, subscriptions, and history across devices
- Handoff continuity between iPhone, iPad, Mac, and Apple TV

**Platforms**
- iOS 18+ / macOS 15+ / tvOS 18+
- Native SwiftUI on every platform
- Customizable home layout, accent colors, and player controls

## Yattee Server

A self-hosted backend powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp) that gives Yattee superpowers.

- **Direct stream URLs** — gets fresh YouTube CDN URLs, bypassing Invidious/Piped blocks and rate limits
- **Play from 1000+ sites** — Vimeo, TikTok, Twitch, Dailymotion, Twitter/X, and anything else yt-dlp supports
- **Invidious-compatible API** — drop-in replacement, works alongside existing Invidious/Piped instances
- **Self-hosted & private** — run on your own hardware, no data leaves your network
- **Fast parallel streaming** — yt-dlp parallel downloading streams video while it downloads
- **Admin panel** — web UI for settings, credentials, and monitoring
- **Docker ready** — single container deployment

Check out the [yattee-server](https://github.com/yattee/yattee-server) repository to get started.

## Documentation

- [Installation](https://github.com/yattee/yattee/wiki/Installation-Instructions)
- [Building](https://github.com/yattee/yattee/wiki/Building-instructions)
- [Features](https://github.com/yattee/yattee/wiki/Features)
- [FAQ](https://github.com/yattee/yattee/wiki/FAQ)
- [Screenshots Gallery](https://github.com/yattee/yattee/wiki/Screenshots-Gallery)
- [Tips](https://github.com/yattee/yattee/wiki/Tips)
- [Integrations](https://github.com/yattee/yattee/wiki/Integrations)
- [Donations](https://github.com/yattee/yattee/wiki/Donations)

## Contributing

Browse the [issues](https://github.com/yattee/yattee/issues) list or open a new one to discuss your idea. Every contribution is welcome.

Join [Discord](https://yattee.stream/discord) or the [Matrix channel](https://matrix.to/#/#yattee:matrix.org) if you need advice or want to discuss the project.

## Translations

Help make Yattee accessible to everyone by contributing translations.

<a href="https://hosted.weblate.org/engage/yattee/">
<img src="https://hosted.weblate.org/widgets/yattee/-/localizable-strings/multi-auto.svg" alt="Translation status" />
</a>

Localization hosting provided by [Weblate](https://weblate.org/en/).

## License

Yattee is shared under the [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.en.html) license.
