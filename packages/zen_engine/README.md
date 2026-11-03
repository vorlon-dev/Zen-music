# zen_engine

The complete, plug-and-play music engine ("brain") for Flutter applications. Extracted directly from the core architecture of ZenMusic.

`zen_engine` provides everything from multi-source search (JioSaavn + YouTube), lossless audio resolution (up to 24-bit / 192 kHz FLAC), time-synced LRC lyrics, playback & queue control, offline downloads, and real-time Listen Together room synchronization.

---

## ✨ Features

- 🎧 **Multi-Source Catalog & Streaming**: Search and stream from JioSaavn (320 kbps AAC) and YouTube Music.
- 💎 **Lossless Stream Resolver**: Multi-tier quality fallback (Hi-Res Max 192k → Hi-Res 96k → FLAC CD 44.1k → MP3 320k).
- 📜 **Time-Synced Lyrics**: LRCLIB and Kugou integration with parsed timestamps (`[mm:ss.xx]`) ready for synced lyric views.
- ⏯️ **Headless Player & Queue Controller**: Built on `just_audio` and `audio_service`, handling queues, shuffle, repeat, session persistence, and real-time playback state streams.
- 💾 **Offline Download Manager**: Background downloads with automatic stream resolution and cache management.
- 👥 **Listen Together (Jam)**: Synchronized multi-user rooms over WebSockets where the host controls playback.
- 🟢 **Spotify Search**: Track and metadata lookup.

---

## 🚀 Getting Started

### 1. Add dependency

Add `zen_engine` to your `pubspec.yaml`:

```yaml
dependencies:
  zen_engine: ^1.0.0
```

### 2. Initialize the Engine

Call `ZenEngine.instance.init()` once in your app's startup:

```dart
import 'package:flutter/material.dart';
import 'package:zen_engine/zen_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZenEngine.instance.init();
  runApp(const MyApp());
}
```

---

## 📖 Usage Examples

### 🔍 Unified Search

Search across JioSaavn and YouTube Music simultaneously:

```dart
// Multi-source search with auto-deduplication
final List<ZenSong> songs = await ZenEngine.search.search('Blinding Lights');

for (final song in songs) {
  print('${song.title} by ${song.artist} (${song.source})');
}
```

### 🎵 Playback & Queue Management

Use `ZenEngine.player` to control audio playback without writing boilerplate audio player logic:

```dart
// Play a single song
await ZenEngine.player.playSong(songs.first);

// Or play a whole playlist / queue starting from index 0
await ZenEngine.player.playQueue(songs, initialIndex: 0);

// Basic playback controls
await ZenEngine.player.pause();
await ZenEngine.player.resume();
await ZenEngine.player.skipNext();
await ZenEngine.player.skipPrevious();
await ZenEngine.player.seek(const Duration(seconds: 45));

// Listen to player state
ZenEngine.player.stateStream.listen((ZenPlayerState state) {
  print('Status: ${state.status}');
  print('Position: ${state.positionState.position} / ${state.positionState.total}');
  print('Current Song: ${state.currentSong?.title}');
});
```

### 📜 Time-Synced Lyrics

Fetch synced lyrics with automatic fallback between LRCLIB and Kugou:

```dart
final Lyrics? lyrics = await ZenEngine.lyrics.getLyrics(
  title: 'Starboy',
  artist: 'The Weeknd',
);

if (lyrics != null && lyrics.parsedLyrics != null) {
  for (final line in lyrics.parsedLyrics!.lyrics) {
    print('[${line.start.inSeconds}s] ${line.text}');
  }
}
```

### 💎 Lossless Audio Resolution

Resolve high-resolution or CD-quality lossless audio streams:

```dart
final String? losslessUrl = await ZenEngine.lossless.resolveStreamUrl(
  song.id,
  targetQuality: LosslessQuality.flacHiRes96,
);

print('Lossless stream URL: $losslessUrl');
```

### 💾 Offline Downloads

Download tracks for offline playback:

```dart
// Start downloading a song
final String? localFilePath = await ZenEngine.downloads.download(song);

// Check if downloaded
if (ZenEngine.downloads.isDownloaded(song.id)) {
  print('Song is ready offline at: $localFilePath');
}
```

### 👥 Listen Together (Jam)

Create or join synchronized playback rooms:

```dart
// As Host
final String? roomId = await ZenEngine.jam.createRoom();
print('Share this room code with friends: $roomId');

// Broadcast currently playing track to room members
ZenEngine.jam.broadcastTrack(song);

// As Guest
await ZenEngine.jam.joinRoom('ROOM_CODE_HERE');
ZenEngine.jam.messagesStream.listen((message) {
  print('Received room event: $message');
});
```

---

## 🛠️ Supported Platforms

- **Android**
- **iOS**
- **Windows**
- **macOS**
- **Linux**
- **Web**

---

## 📄 License

GPL-3.0 - see [LICENSE](LICENSE) for details.
