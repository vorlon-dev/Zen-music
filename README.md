# 🎵 ZenMusic

A multi-source Flutter music player with a Listen Together mode

![Status](https://img.shields.io/badge/status-under%20development-orange)
![Platform](https://img.shields.io/badge/platform-Flutter-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

> ⚠️ **UNDER ACTIVE DEVELOPMENT**
> This project is still in development. Features may change, break, or disappear between commits. Anything you build from this source is at your own risk — see the [Disclaimer](#️-disclaimer) at the bottom.

## 📖 About

ZenMusic is an Android music player built with Flutter that streams from multiple sources — YouTube, YouTube Music and JioSaavn — behind one clean, dark interface. It grew out of a simple question: what if one app could do everything?

Right now you can:

- Stream songs from YouTube / YT Music / JioSaavn with automatic fallback between sources
- Download songs and play them completely offline
- **Listen Together** — create a room, share the code, and everyone hears the same song at the same moment, in perfect sync
- Like songs, build playlists, and keep a listening history with a monthly recap
- View synced lyrics with word-level highlighting
- Install community extensions (`.eapk`) to add entirely new music sources at runtime — the same extension system used by [Echo](https://github.com/brahmkshatriya/echo)
- Fine-tune playback with a system equalizer, sleep timer, audio quality settings and more

Everything streams on demand. ZenMusic does not host, store or distribute any music — see the [Disclaimer](#️-disclaimer).

## ✨ Features

### 🎧 Playback
- Multi-source streaming: YouTube · YouTube Music · JioSaavn (320 kbps)
- Automatic source fallback — if one extractor fails, the next takes over
- Background playback with a full media notification and lock-screen controls
- Radio mode: every song seeds an endless related-songs queue
- Shuffle, repeat (one/all), queue management with drag & reorder
- Audio quality settings (low / medium / high)
- System equalizer support (Android)

### 📥 Offline
- Download any song with a single tap and a live progress ring
- Downloaded tracks play with zero network access
- A dedicated Downloads shelf in your library, with per-song and clear-all deletion

### 🌐 Listen Together
- Create a room and share an 8-character code
- Everyone hears the same track at the same moment — play, pause, seek and skip are mirrored live, with server-time drift correction
- Host controls: approve or reject join requests, remove users
- Guests can suggest tracks (suggestions land with the host)
- Automatic reconnection with a 15-minute session grace window
- Powered by a self-hosted [metroserver](https://github.com/MetrolistGroup/metroserver) instance

### 🧩 Extensions
- Install community `.eapk` extensions to add new sources
- Extensions run in a native `DexClassLoader` host implementing the [Echo](https://github.com/brahmkshatriya/echo) extension contract
- Per-extension home feeds, detail pages, search, streaming and host-approval flow

### 📝 Lyrics
- Time-synced lyrics with smooth word-level highlighting ([LRCLIB](https://lrclib.net/))
- Automatic fallback to estimated timing for plain-text lyrics
- A "synced" badge tells you which is which

### 🎨 Interface
- Dark, Spotify-inspired UI rebuilt in the design language of [Echo Nightly](https://github.com/brahmkshatriya/echo)
- Animated wave seek bar, morphing play/pause button, "now playing" visualizer badges
- Shared-axis page transitions and animated navigation
- Paytone One display typography

### 📊 Extras
- Listening statistics with a monthly recap card
- Search across songs, videos, playlists and albums from multiple sources in parallel
- Backup & restore (liked songs + playlists → JSON)
- Update checks

<!--
Screenshots
Add 2–4 images here (home, player, listen together) once available.
Place them in a screenshots/ folder and reference them like:
![Home](screenshots/home.png) ![Player](screenshots/player.png)
-->

## 🚧 Roadmap

- [x] Multi-source streaming & fallback
- [x] Extension system (install / select / home feed / detail / search / stream)
- [x] Listen Together (rooms, host approval, sync, reconnect)
- [x] Offline downloads
- [x] Liked songs & playlists
- [x] Lyrics (synced + plain)
- [ ] Playlist management (rename, reorder, remove songs)
- [ ] Listen Together: track suggestions UI polish
- [ ] iOS support

## 🛠️ Building from source

### Requirements

| Tool | Version |
|---|---|
| Flutter | 3.x |
| Android Studio | with SDK 34+ |
| Java | 17 |
| Git | with submodule support |

### Steps

```bash
# 1. Clone with submodules (the Echo extension contract is referenced
#    by the native extension host)
git clone --recurse-submodules <this-repo-url>
cd zenmusic

# 2. Fetch dependencies
flutter pub get

# 3. Run
flutter run
```

### Listen Together server

Listen Together requires a running [metroserver](https://github.com/MetrolistGroup/metroserver) instance. It ships as a single Docker container:

```bash
docker run -d \
  -p 8080:8080 \
  -e PORT=8080 \
  -e DATABASE_FILE=/app/data/metroserver.db \
  -v metroserver-data:/app/data \
  --name metroserver \
  ghcr.io/MetrolistGroup/metroserver:latest
```

Point the app at your instance (see in-app settings), and you're set — any deployment platform that supports Docker + WebSocket passthrough works, including free tiers.

## 🧩 Architecture (short version)

```
Flutter UI (dark, Echo-inspired)
        │
   audio_service + just_audio  ── background playback, queue, EQ
        │
   ┌────┴─────────┬──────────────┬──────────────┐
   │               │              │              │
YouTube        JioSaavn       Extensions    Listen Together
(yt_extractor +  (unofficial   (DexClassLoader  (metroserver
 youtube_explode)  320kbps API)  host, .eapk)     WebSocket +
                                                    protobuf)
```

The extension host implements the [Echo](https://github.com/brahmkshatriya/echo) extension contract: community `.eapk` packages are loaded at runtime and can provide home feeds, search, detail pages and full streaming — the same way Echo does.

## 🙏 Credits & Acknowledgements

ZenMusic stands on the shoulders of these projects and people. Huge thank-you to all of them:

**Core inspiration & contracts**
- [@brahmkshatriya](https://github.com/brahmkshatriya) — [Echo](https://github.com/brahmkshatriya/echo) — the extension contract (`echo.common`), the `DexClassLoader` host design and the Nightly UI design language that ZenMusic's interface is modelled on. Parts of this project's native extension layer are derived from Echo, which is why ZenMusic is licensed GPL-3.0.
- [@nyxiereal](https://github.com/nyxiereal) & [MetrolistGroup](https://github.com/MetrolistGroup) — [metroserver](https://github.com/MetrolistGroup/metroserver) — the high-performance Go WebSocket server powering Listen Together, and [Metrolist](https://github.com/MetrolistGroup) where the Listen Together concept comes from.

**Streaming & data**
- [yt_extractor](https://pub.dev/packages/yt_extractor) — YouTube extraction (streams, search, related)
- [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) — YouTube InnerTube access with custom clients
- [saavn.dev](https://saavn.dev/) — the unofficial JioSaavn API powering 320 kbps streaming and catalogs

**Audio & media**
- [just_audio](https://pub.dev/packages/just_audio), [audio_service](https://pub.dev/packages/audio_service), [audio_session](https://pub.dev/packages/audio_session) by [@ryanheise](https://github.com/ryanheise) — the audio backbone

**Packages**
- [provider](https://pub.dev/packages/provider) · [hive](https://pub.dev/packages/hive) · [shared_preferences](https://pub.dev/packages/shared_preferences) · [cached_network_image](https://pub.dev/packages/cached_network_image) · [flutter_lyric](https://pub.dev/packages/flutter_lyric) · [file_picker](https://pub.dev/packages/file_picker) · [web_socket_channel](https://pub.dev/packages/web_socket_channel) · [webview_flutter](https://pub.dev/packages/webview_flutter) · [video_player](https://pub.dev/packages/video_player) · [http](https://pub.dev/packages/http)

**Design & icons**
- [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons) by Microsoft (MIT)
- [Paytone One](https://fonts.google.com/specimen/Paytone+One) typeface (SIL Open Font License)
- [LRCLIB](https://lrclib.net/) — the free, open lyrics API
- Spotify — the original dark-interface inspiration

## 📄 License

This project is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).

Because portions of the native extension layer are derived from [Echo](https://github.com/brahmkshatriya/echo) (GPL-3.0), the complete work must remain GPL-3.0 and source-available. That's not a burden — it's the deal that makes projects like this possible.

## ⚠️ Disclaimer

- ZenMusic is provided strictly for educational and personal use, "as-is", without warranty of any kind.
- ZenMusic does not host, store, mirror or distribute any copyrighted content. All audio is streamed on demand from third-party platforms through their unofficial, publicly accessible APIs.
- Users are responsible for ensuring their use complies with the laws of their country and the terms of service of those platforms.
- This project is not affiliated with, endorsed by, or connected to YouTube, Google, JioSaavn, Spotify or any other platform mentioned.
- If you are a rights holder and believe something here infringes your rights, please open an issue and it will be addressed promptly.

---

Made with Flutter and too many late nights.