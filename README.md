# <img src="screenshots/logo.png" alt="ZenMusic Logo" width="40" align="center"/> ZenMusic

A modern Android music player with multi-source streaming, synced lyrics, offline playback and Listen Together.

## Table of Contents
- [Overview](#overview)
- [Screenshots](#screenshots)
- [Features](#features)
- [Installation](#installation)
- [Resources & Credits](#resources--credits)
- [Contributing](#contributing)
- [Legal](#legal)

## Overview

ZenMusic is a Flutter-based music player for Android. It streams from multiple sources (JioSaavn and YouTube Music), supports offline downloads, real-time synchronized lyrics, and lets you listen together with friends in perfect sync.

> [!IMPORTANT]
> This app is still in development. Features may change and you may run into bugs. Updates are delivered through GitHub Releases — download the latest APK from the [Releases Page](../../releases).

## Screenshots

| Home Screen | Player | Lyrics |
|---|---|---|
| ![Home Screen](screenshots/home.png) | ![Player](screenshots/player.png) | ![Lyrics](screenshots/lyrics.png) |

| Listen Together | Search | Library |
|---|---|---|
| ![Listen Together](screenshots/listen_together.png) | ![Search](screenshots/library.png) | ![Library](screenshots/library.png) |

## Features

- **Multi-Source Streaming** — JioSaavn (320 kbps AAC) and YouTube Music, with source extensions.
- **Listen Together** — Create a room, share the code, and listen in perfect sync. The host controls playback for everyone.
- **Synced Lyrics** — Time-synchronized lyrics with adjustable size, spacing and alignment.
- **Offline Downloads** — Download songs and play them without a network connection.
- **Song Recognition** — Identify music playing around you and play it instantly.
- **Ambient Mode** — Landscape player with an animated glow background built from the album art.
- **Sleep Timer & Equalizer** — System equalizer with bass and treble controls, sleep timer with end-of-song option.
- **Appearance Settings** — Player background styles, three progress slider styles, thumbnail radius, haptics and more.
- **Import from Spotify** — Bring your playlists over from a CSV export.
- **OTA Updates** — The app checks GitHub Releases and tells you when a new version is out.

## Installation

Download the latest APK from the [Releases Page](../../releases) and install it on your Android device.

### Building from Source

```bash
git clone https://github.com/vorlon-dev/Zen-music.git
cd Zen-music
flutter pub get
flutter run
```

## Resources & Credits

ZenMusic stands on the shoulders of excellent open-source projects. Sincere thanks to:

| Project                      | Contribution |
|------------------------------|---|
| [Echo nightly](#)            | Extension Implementation             |
| [Echo muisc](#)              | UI design language, Listen Together client, recognition engine, Apple Music canvas and welcome dialog |
| [Metrolist / metroserver](#) | Listen Together server protocol and deployment |
| [Musify](#)                  | Streaming and app architecture reference |

Additional thanks:

- `youtube_explode_dart` and `yt_extractor` — YouTube stream extraction
- `audio_service` and `just_audio` — playback engine
- `flutter_lyric` — lyrics rendering
- Shazam discovery API and the dejavu-fingerprinter algorithm — song recognition
- [LRCLIB](https://lrclib.net/) — synced lyrics provider
- Music Recognizer — recognition flow reference

## Contributing

Contributions are welcome.

1. Fork the repository.
2. Create a branch for your change:
   ```bash
   git checkout -b feature/my-feature
   ```
3. Make your changes and commit with a clear message.
4. Push to your fork and open a Pull Request describing what changed and why.

Please keep pull requests focused on a single change, and test on a real device before submitting.

## Legal

ZenMusic is a fully open-source project created for educational purposes and personal use. It is not monetized in any way — there are no advertisements, premium features or subscriptions.

The app acts strictly as a client to publicly available content and APIs of the platforms it supports. We do not host, upload, distribute or store any audio, video or copyrighted media files. All content is served by the respective platforms and remains the property of its copyright owners.

This software is provided "AS IS", without warranty of any kind. Users are solely responsible for ensuring their usage complies with their local copyright laws and the Terms of Service of the platforms they access.

Licensed under [GPL-3.0](LICENSE)