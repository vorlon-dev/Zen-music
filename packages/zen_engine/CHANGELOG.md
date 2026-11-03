## 1.0.0

- Initial release of `zen_engine`: the complete headless music engine for Flutter.
- Multi-source streaming & catalog: JioSaavn (up to 320 kbps AAC) and YouTube Music stream extraction.
- Unified search engine across JioSaavn and YouTube with deduplication.
- Lossless audio stream resolver supporting MP3 320, FLAC CD, Hi-Res 96kHz, and Hi-Res Max 192kHz fallback.
- Lyrics engine supporting time-synced LRC from LRCLIB and Kugou.
- Headless `ZenPlayerController` with queue management, shuffle, repeat, session persistence, and state streams.
- Offline download and local cache manager.
- Real-time Listen Together room synchronization engine (WebSockets).
- Headless Spotify search and metadata lookup.
