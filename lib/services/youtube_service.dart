import 'dart:async';
import 'dart:convert';
import 'package:yt_extractor/yt_extractor.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;
import '../models/song.dart';
import 'jiosaavn_service.dart';

class VideoStreamResult {
  final String url;
  final Map<String, String> headers;

  /// Stream type for the quality badge: 'opus', 'aac', 'mp3', 'flac'...
  final String? audioType;

  /// Actual bitrate in kbps (for the badge).
  final int? bitrateKbps;

  const VideoStreamResult(this.url,
      [this.headers = const {}, this.audioType, this.bitrateKbps]);
}

class YoutubeService {
  static bool videoEnabled = true;

  final _extractor = YtExtractor();
  final _yt = yt_explode.YoutubeExplode();
  final _jiosaavn = JiosaavnService();
  final _probe = http.Client();
  final _ytmClient = http.Client();

  bool _extractorInitialized = false;

  final Map<String, String> _videoIdCache = {};
  // In-flight video-id resolutions — concurrent callers for the same
  // song share one lookup instead of duplicating the whole search.
  final Map<String, Future<String?>> _videoIdInFlight = {};

  /// 'low' | 'medium' | 'high' — caps audio bitrate selection.
  String _audioQuality = 'high';
  String get audioQuality => _audioQuality;
  void setAudioQualitySetting(String q) => _audioQuality = q;

  int _maxBitrateFor(String quality) =>
      quality == 'low' ? 96000 : (quality == 'medium' ? 160000 : 1000000);

  DateTime? _lastRequestTime;
  static const _minRequestInterval = Duration(milliseconds: 1200);

  Future<void> _throttle() async {
    final now = DateTime.now();
    if (_lastRequestTime != null) {
      final elapsed = now.difference(_lastRequestTime!);
      if (elapsed < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  Future<void> _ensureExtractorInit() async {
    if (_extractorInitialized) return;
    // A hung init must never stall the whole resolution chain.
    await _extractor.init().timeout(const Duration(seconds: 12));
    _extractorInitialized = true;
  }

  // ═════════════════════════════════════════════
  // CLIENTS — synced with yt-dlp master (2026-08-18)
  // ═════════════════════════════════════════════

  static final yt_explode.YoutubeApiClient visionOs =
  yt_explode.YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'userAgent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
        },
      },
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  static const _visionOsUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static final yt_explode.YoutubeApiClient webEmbedded =
  yt_explode.YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'WEB_EMBEDDED_PLAYER',
          'clientVersion': '2.20260708.00.00',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
        },
      },
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  static final yt_explode.YoutubeApiClient tvDowngraded =
  yt_explode.YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'TVHTML5',
          'clientVersion': '5.20260707',
          'userAgent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
        },
      },
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  static final yt_explode.YoutubeApiClient tvFresh =
  yt_explode.YoutubeApiClient(
    {
      'context': {
        'client': {
          'deviceMake': '',
          'deviceModel': '',
          'userAgent':
          'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
          'clientName': 'TVHTML5',
          'clientVersion': '7.20260707.07.00',
          'hl': 'en',
          'gl': 'US',
          'utcOffsetMinutes': 0,
          'originalUrl': 'https://www.youtube.com/tv',
          'theme': 'CLASSIC',
          'platform': 'DESKTOP',
          'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
          'webpSupport': false,
          'configInfo': {},
          'tvAppInfo': {'appQuality': 'TV_APP_QUALITY_FULL_ANIMATION'},
          'acceptHeader':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        'user': {'lockedSafetyMode': false},
        'request': {'useSsl': true},
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  static final yt_explode.YoutubeApiClient iosFresh =
  yt_explode.YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'IOS',
          'clientVersion': '21.26.4',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone16,2',
          'userAgent':
          'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
          'hl': 'en',
          'platform': 'MOBILE',
          'osName': 'IOS',
          'osVersion': '18.3.2.22D82',
          'timeZone': 'UTC',
          'gl': 'US',
          'utcOffsetMinutes': 0,
        },
      },
    },
    'https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc&prettyPrint=false',
  );

  static final List<_HdClient> _hdClients = [
    _HdClient('visionOs', visionOs, _visionOsUa),
    _HdClient('webEmbedded', webEmbedded, null),
    _HdClient('tvDowngraded', tvDowngraded,
        'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version'),
    _HdClient(
        'tv',
        tvFresh,
        'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)'),
    _HdClient('ios', iosFresh,
        'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)'),
  ];

  static const _safariUa = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)';

  static const List<String> _invidiousInstances = [
    'https://yewtu.be',
    'https://inv.nadeko.net',
    'https://invidious.f5.si',
    'https://invidious.privacyredirect.com',
  ];

  // ═════════════════════════════════════════════
  // YT MUSIC RADIO (WEB_REMIX next endpoint)
  // ═════════════════════════════════════════════

  static const _ytmBase = 'https://music.youtube.com/youtubei/v1';
  static const _ytmApiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const _ytmContext = {
    'context': {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240101.01.00',
        'hl': 'en',
      },
    },
  };

  Future<List<Song>> getYtmRadio(String videoId) async {
    try {
      final uri =
      Uri.parse('$_ytmBase/next?key=$_ytmApiKey&prettyPrint=false');
      final resp = await _ytmClient
          .post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode({
          ..._ytmContext,
          'videoId': videoId,
          'params': 'wAEB',
        }),
      )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) {
        print('📻 YTM radio: status ${resp.statusCode}');
        return [];
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return [];

      final results = _findRenderers(decoded, 'playlistPanelVideoRenderer');
      final songs = <Song>[];
      final seen = <String>{};

      for (final item in results) {
        final vid = (item['videoId'] as String?) ??
            item
                .getMap('navigationEndpoint')
                ?.getMap('watchEndpoint')
                ?.getValue<String>('videoId');
        if (vid == null || vid.isEmpty || !seen.add(vid)) continue;

        final title = _runsText(item.getMap('title')) ??
            _runsText(item.getMap('longBylineText'));
        if (title == null || title.isEmpty) continue;

        final byline = _runsText(item.getMap('longBylineText')) ??
            _runsText(item.getMap('shortBylineText')) ??
            'Unknown';
        final artist = byline.split('•').first.trim();

        final lengthText = _runsText(item.getMap('lengthText'));
        Duration? duration;
        if (lengthText != null) {
          final parts = lengthText.trim().split(':');
          if (parts.length == 2) {
            final m = int.tryParse(parts[0]);
            final s = int.tryParse(parts[1]);
            if (m != null && s != null) {
              duration = Duration(minutes: m, seconds: s);
            }
          } else if (parts.length == 3) {
            final h = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            final s = int.tryParse(parts[2]);
            if (h != null && m != null && s != null) {
              duration = Duration(hours: h, minutes: m, seconds: s);
            }
          }
        }

        final thumbs = item.getMap('thumbnail')?.getList('thumbnails');
        String thumb = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
        if (thumbs != null && thumbs.isNotEmpty && thumbs.last is Map) {
          final url = (thumbs.last as Map)['url']?.toString();
          if (url != null && url.isNotEmpty) thumb = url;
        }

        songs.add(Song(
          id: vid,
          title: title,
          artist: artist,
          thumbnail: thumb,
          duration: duration ?? Duration.zero,
        ));
        if (songs.length >= 25) break;
      }

      print('📻 YTM radio: ${songs.length} tracks for $videoId');
      return songs;
    } catch (e) {
      print('📻 YTM radio failed: $e');
      return [];
    }
  }

  String? _runsText(_JsonMap? node) {
    final runs = node?.getList('runs');
    if (runs == null || runs.isEmpty) return null;
    return runs
        .map((r) => r is Map ? (r['text']?.toString() ?? '') : '')
        .join();
  }

  Iterable<_JsonMap> _findRenderers(dynamic node, String key) sync* {
    if (node is Map) {
      final match = node[key];
      if (match is Map) yield _JsonMap.from(match);
      for (final value in node.values) {
        yield* _findRenderers(value, key);
      }
    } else if (node is List) {
      for (final value in node) {
        yield* _findRenderers(value, key);
      }
    }
  }

  // ═════════════════════════════════════════════
  // SEARCH
  // ═════════════════════════════════════════════

  Future<List<Song>> search(
      String query, {
        SearchFilter filter = SearchFilter.musicSongs,
      }) async {
    await _throttle();

    if (filter == SearchFilter.videos) {
      return await _youtubeVideoSearch(query);
    }

    final combined = <Song>[];

    final jsResults = await _jiosaavn.search(query, limit: 15);
    combined.addAll(jsResults);
    print('🎧 JioSaavn: ${jsResults.length} songs');

    try {
      await _ensureExtractorInit();
      final page = await _extractor
          .search(query, filter: SearchFilter.musicSongs)
          .timeout(const Duration(seconds: 8));
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid == null) continue;
        combined.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/maxresdefault.jpg',
          duration: Duration(seconds: item.duration ?? 0),
        ));
      }
      print('🎵 YouTube Music: added ${combined.length - jsResults.length}');
    } catch (e) {
      print('YouTube Music search failed: $e');
    }

    return _deduplicateByTitle(combined);
  }

  Future<List<Song>> _youtubeVideoSearch(String query) async {
    try {
      final results =
      await _yt.search.search(query).timeout(const Duration(seconds: 8));
      final songs = <Song>[];
      for (final v in results) {
        songs.add(Song(
          id: v.id.value,
          title: v.title,
          artist: v.author,
          thumbnail: 'https://i.ytimg.com/vi/${v.id.value}/maxresdefault.jpg',
          duration: v.duration ?? Duration.zero,
        ));
      }
      print('📹 YouTube videos: ${songs.length}');
      return _deduplicateByTitle(songs);
    } catch (e) {
      print('YouTube video search failed: $e');
      return [];
    }
  }

  List<Song> _deduplicateByTitle(List<Song> songs) {
    final seen = <String>{};
    final result = <Song>[];
    for (final s in songs) {
      final key = _normalizeTitle(s.title);
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(s);
    }
    return result;
  }

  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\s*-\s*topic.*$'), '')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ═════════════════════════════════════════════
  // AUDIO STREAM — quality-capped, URL + headers + type info
  // ═════════════════════════════════════════════

  Future<VideoStreamResult> getAudioStreamUrl(Song song) async {
    await _throttle();

    // Tier 1: JioSaavn 320kbps AAC.
    if (song.isFromJiosaavn) {
      if (song.hasHighQuality) {
        return VideoStreamResult(song.jiosaavnStreamUrl!, const {}, 'AAC', 320);
      }
      final url = await _jiosaavn.fetchStreamUrl(song.jiosaavnId!);
      if (url != null && url.isNotEmpty) {
        return VideoStreamResult(url, const {}, 'AAC', 320);
      }
    }

    // Tier 2: visionOs audio-only + UA headers, quality-capped.
    final v = await _audioAttempt(
      song.id,
      _HdClient('visionOs', visionOs, _visionOsUa),
    );
    if (v != null) return v;

    // Tier 3: yt_extractor (probed).
    try {
      await _ensureExtractorInit();
      final info = await _extractor
          .getStreamInfo('https://www.youtube.com/watch?v=${song.id}')
          .timeout(const Duration(seconds: 8));
      final audio = info.bestAudioStream;
      if (audio != null && audio.url.isNotEmpty) {
        if (await _isPlayable(audio.url, null)) {
          print('✅ Audio: yt_extractor ok (${song.id})');
          return VideoStreamResult(audio.url, const {}, _typeFromUrl(audio.url),
              _kbpsFromStream(audio));
        }
        print('↳ yt_extractor URL gated — skipped');
      }
    } catch (e) {
      print('yt_extractor failed: $e');
    }

    // Tier 4: legacy clients, probed (last-ditch).
    for (final entry in [
      _HdClient(
        'androidSdkless',
        yt_explode.YoutubeApiClient.androidSdkless,
        'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      ),
      _HdClient('androidVr', yt_explode.YoutubeApiClient.androidVr, null),
    ]) {
      final r = await _audioAttempt(song.id, entry);
      if (r != null) return r;
    }

    throw Exception('All audio extractors failed for ${song.title}');
  }

  Future<VideoStreamResult?> _audioAttempt(
      String videoId, _HdClient entry) async {
    await _throttle();
    print('🎵 Audio: trying ${entry.name} for $videoId ...');
    try {
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [entry.client],
      ).timeout(const Duration(seconds: 10));
      if (manifest.audioOnly.isEmpty) {
        print('   ↳ ${entry.name}: no audio-only streams');
        return null;
      }

      // Quality cap: prefer streams at/under the setting; fall back to
      // the best available if nothing fits.
      final maxBps = _maxBitrateFor(_audioQuality);
      final capped = manifest.audioOnly
          .where((s) => s.bitrate.bitsPerSecond <= maxBps)
          .toList();
      final pool = capped.isNotEmpty ? capped : manifest.audioOnly;
      final best = pool.withHighestBitrate();
      final url = best.url.toString();

      if (!await _isPlayable(url, entry.userAgent)) {
        print('   ↳ ${entry.name}: URL blocked (403/network)');
        return null;
      }
      final ua = entry.userAgent;
      final headers = ua == null
          ? const <String, String>{}
          : <String, String>{'User-Agent': ua};
      final kbps = best.bitrate.kiloBitsPerSecond.round();
      print('✅ Audio: ${entry.name} ok ($videoId, ${kbps}kbps)');
      return VideoStreamResult(
          url, headers, _typeFromUrl(url), kbps);
    } catch (e) {
      print('   ↳ ${entry.name} audio failed — $e');
      return null;
    }
  }


  String _typeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('.flac')) return 'FLAC';
    if (u.contains('.webm') || u.contains('opus')) return 'OPUS';
    if (u.contains('.m4a') || u.contains('.mp4') || u.contains('aac')) {
      return 'AAC';
    }
    if (u.contains('.mp3')) return 'MP3';
    return 'AUDIO';
  }

  int? _kbpsFromStream(dynamic stream) {
    try {
      return stream.bitrate.kiloBitsPerSecond.round();
    } catch (_) {
      return null;
    }
  }

  // ═════════════════════════════════════════════
  // VIDEO STREAM — Canvas backdrop
  // ═════════════════════════════════════════════

  Future<VideoStreamResult?> getVideoStreamUrl(Song song,
      {bool preferHd = true}) async {
    if (!videoEnabled) return null;

    final videoId = await getVideoId(song);
    if (videoId == null || videoId.isEmpty) {
      print('🎬 Video: no YouTube id for "${song.title}"');
      return null;
    }

    if (preferHd) {
      final v = await _progressiveAttempt(
          videoId, _HdClient('visionOs', visionOs, _visionOsUa));
      if (v != null) return v;

      final hls = await _resolveHlsStream(videoId);
      if (hls != null) return hls;

      final inv = await _resolveInvidiousStream(videoId);
      if (inv != null) return inv;

      for (final entry in _hdClients.skip(1)) {
        final r = await _progressiveAttempt(videoId, entry);
        if (r != null) return r;
      }
    }

    await _throttle();
    print('🎬 Video: resolving SD muxed (default client) for $videoId ...');
    try {
      final manifest = await _yt.videos.streams
          .getManifest(videoId)
          .timeout(const Duration(seconds: 10));
      if (manifest.muxed.isEmpty) {
        print('🎬 Video: no muxed streams for $videoId');
        return null;
      }
      final best = manifest.muxed.withHighestBitrate();
      print('✅ Video: SD muxed ${best.videoQualityLabel} ($videoId)');
      return VideoStreamResult(best.url.toString());
    } catch (e) {
      print('❌ Video: SD muxed failed for $videoId — $e');
      return null;
    }
  }

  Future<VideoStreamResult?> _progressiveAttempt(
      String videoId, _HdClient entry) async {
    await _throttle();
    print('🎬 Video: trying ${entry.name} for $videoId ...');
    try {
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [entry.client],
      ).timeout(const Duration(seconds: 10));

      final mp4Only = manifest.videoOnly
          .where((s) => s.container == yt_explode.StreamContainer.mp4)
          .toList();

      String? url;
      if (mp4Only.isNotEmpty) {
        dynamic pick;
        for (final target in const [1080, 720]) {
          for (final s in mp4Only) {
            if (_streamHeight(s) == target) {
              pick = s;
              break;
            }
          }
          if (pick != null) break;
        }
        if (pick == null) {
          dynamic best;
          for (final s in mp4Only) {
            final h = _streamHeight(s);
            if (h <= 1080 && (best == null || h > _streamHeight(best))) {
              best = s;
            }
          }
          pick = best ?? mp4Only.withHighestBitrate();
        }
        print('   ↳ ${entry.name} candidate: ${pick.videoQualityLabel}');
        url = pick.url.toString();
      } else if (manifest.videoOnly.isNotEmpty) {
        final best = manifest.videoOnly.withHighestBitrate();
        print('   ↳ ${entry.name} candidate: '
            '${best.videoQualityLabel} (non-mp4)');
        url = best.url.toString();
      } else {
        print('   ↳ ${entry.name}: no video-only streams');
        return null;
      }

      if (!await _isPlayable(url, entry.userAgent)) {
        print('   ↳ ${entry.name}: URL blocked (403/network) — next');
        return null;
      }

      final ua = entry.userAgent;
      final headers = ua == null
          ? const <String, String>{}
          : <String, String>{'User-Agent': ua};

      print('✅ Video: HD stream via ${entry.name} ($videoId)');
      return VideoStreamResult(url, headers);
    } catch (e) {
      print('   ↳ ${entry.name} failed — $e');
      return null;
    }
  }

  static int _streamHeight(dynamic s) {
    final m = RegExp(r'^(\d+)').firstMatch('${s.videoQualityLabel}');
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  // ═════════════════════════════════════════════
  // HLS TIER (safari client)
  // ═════════════════════════════════════════════

  Future<VideoStreamResult?> _resolveHlsStream(String videoId) async {
    await _throttle();
    print('🎬 Video: trying HLS (safari) for $videoId ...');
    try {
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [yt_explode.YoutubeApiClient.safari],
      ).timeout(const Duration(seconds: 10));
      final hls = manifest.hls;
      if (hls.isEmpty) {
        print('   ↳ safari: no HLS streams');
        return null;
      }

      for (final entry in hls) {
        final playlistUrl = entry.url;
        try {
          final resp = await _probe
              .get(playlistUrl)
              .timeout(const Duration(seconds: 5));
          if (resp.statusCode != 200) {
            print('   ↳ HLS playlist status ${resp.statusCode} — next');
            continue;
          }
          final body = resp.body;

          if (body.contains('#EXT-X-STREAM-INF')) {
            final variant = _pickHlsVariant(playlistUrl, body);
            if (variant == null) {
              print('   ↳ HLS master parsed but no usable variant');
              continue;
            }
            print('✅ Video: HLS variant ${variant.label} ($videoId)');
            return VideoStreamResult(
              variant.url,
              {'User-Agent': _safariUa},
            );
          }

          print('✅ Video: HLS media playlist, single quality ($videoId)');
          return VideoStreamResult(
            playlistUrl.toString(),
            {'User-Agent': _safariUa},
          );
        } catch (e) {
          print('   ↳ HLS entry failed — $e');
          continue;
        }
      }
      return null;
    } catch (e) {
      print('   ↳ safari manifest failed — $e');
      return null;
    }
  }

  _HlsVariant? _pickHlsVariant(Uri masterUrl, String body) {
    final lines = body.split('\n');
    final variants = <_HlsVariant>[];
    final heights = <int>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final m = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      if (m == null || next.isEmpty || next.startsWith('#')) continue;
      final h = int.parse(m.group(2)!);
      variants.add(_HlsVariant(
        masterUrl.resolve(next).toString(),
        '${m.group(1)}x$h',
      ));
      heights.add(h);
    }
    if (variants.isEmpty) return null;

    for (var i = 0; i < variants.length; i++) {
      if (heights[i] == 1080) return variants[i];
    }
    for (var i = 0; i < variants.length; i++) {
      if (heights[i] == 720) return variants[i];
    }
    int? bestIdx;
    for (var i = 0; i < variants.length; i++) {
      if (heights[i] <= 1080 &&
          (bestIdx == null || heights[i] > heights[bestIdx])) {
        bestIdx = i;
      }
    }
    if (bestIdx != null) return variants[bestIdx];
    var largest = 0;
    for (var i = 1; i < variants.length; i++) {
      if (heights[i] > heights[largest]) largest = i;
    }
    return variants[largest];
  }

  // ═════════════════════════════════════════════
  // INVIDIOUS TIER (proxied)
  // ═════════════════════════════════════════════

  Future<VideoStreamResult?> _resolveInvidiousStream(String videoId) async {
    for (final base in _invidiousInstances) {
      print('🎬 Video: trying Invidious $base for $videoId ...');
      try {
        final uri = Uri.parse('$base/api/v1/videos/$videoId?local=true');
        final resp =
        await _probe.get(uri).timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) {
          print('   ↳ $base status ${resp.statusCode} — next instance');
          continue;
        }
        final dynamic decoded = jsonDecode(resp.body);
        if (decoded is! Map<String, dynamic>) continue;

        final formatStreams = decoded['formatStreams'] as List<dynamic>? ?? [];
        for (final f in formatStreams) {
          if (f is! Map) continue;
          final url = f['url'];
          if ('${f['itag']}' == '22' && url is String && url.isNotEmpty) {
            if (await _isPlayable(url, null)) {
              print('✅ Video: Invidious muxed 720p ($videoId via $base)');
              return VideoStreamResult(url);
            }
            print('   ↳ $base: itag 22 URL not playable — next instance');
          }
        }

        final adaptive = decoded['adaptiveFormats'] as List<dynamic>? ?? [];
        String? bestUrl;
        var bestHeight = 0;
        for (final f in adaptive) {
          if (f is! Map) continue;
          final type = '${f['type']}';
          if (!type.startsWith('video/mp4')) continue;
          final url = f['url'];
          if (url is! String || url.isEmpty) continue;
          final label = '${f['qualityLabel']}';
          final height =
              int.tryParse(label.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          if (height == 720) {
            if (await _isPlayable(url, null)) {
              print('✅ Video: Invidious video-only 720p ($videoId via $base)');
              return VideoStreamResult(url);
            }
            print('   ↳ $base: 720p URL not playable — next instance');
          }
          if (height > bestHeight && height <= 720) {
            bestHeight = height;
            bestUrl = url;
          }
        }
        if (bestUrl != null && await _isPlayable(bestUrl, null)) {
          print('✅ Video: Invidious video-only ${bestHeight}p '
              '($videoId via $base)');
          return VideoStreamResult(bestUrl);
        }
        print('   ↳ $base: no usable mp4 streams');
      } catch (e) {
        print('   ↳ $base failed — $e');
        continue;
      }
    }
    return null;
  }

  Future<bool> _isPlayable(String url, String? userAgent) async {
    try {
      final headers = <String, String>{'Range': 'bytes=0-1'};
      final ua = userAgent;
      if (ua != null) headers['User-Agent'] = ua;
      final resp = await _probe
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 4));
      return resp.statusCode == 200 || resp.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  // ═════════════════════════════════════════════
  // VIDEO ID — resolution (all song types) + cache
  // ═════════════════════════════════════════════

  Future<String?> getVideoId(Song song) async {
    if (!videoEnabled) return null;
    if (!song.isFromJiosaavn) return song.id;

    final cached = _videoIdCache[song.id];
    if (cached != null) return cached;

    // Concurrent callers (radio fill + related + player UI) share one
    // lookup instead of duplicating the whole search chain.
    final inFlight = _videoIdInFlight[song.id];
    if (inFlight != null) return inFlight;

    final future = _resolveVideoId(song);
    _videoIdInFlight[song.id] = future;
    try {
      return await future;
    } finally {
      _videoIdInFlight.remove(song.id);
    }
  }

  Future<String?> _resolveVideoId(Song song) async {
    final query = '${song.title} ${song.artist}';

    try {
      await _ensureExtractorInit();
      final page = await _extractor
          .search(query, filter: SearchFilter.musicVideos)
          .timeout(const Duration(seconds: 8));
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid != null) {
          _videoIdCache[song.id] = vid;
          print('🎬 Resolved (yt_extractor) "${song.title}" → $vid');
          return vid;
        }
      }
    } catch (e) {
      print('getVideoId yt_extractor failed: $e');
    }

    try {
      await _throttle();
      final results =
      await _yt.search.search(query).timeout(const Duration(seconds: 8));
      if (results.isNotEmpty) {
        final vid = results.first.id.value;
        _videoIdCache[song.id] = vid;
        print('🎬 Resolved (youtube_explode) "${song.title}" → $vid');
        return vid;
      }
    } catch (e) {
      print('getVideoId youtube_explode failed: $e');
    }

    print('🎬 No YouTube video found for "${song.title}"');
    return null;
  }

  // ═════════════════════════════════════════════
  // RELATED SONGS — YTM radio first, extractors second
  // ═════════════════════════════════════════════

  Future<List<Song>> getRelatedSongs(Song seedSong) async {
    await _throttle();

    String? youtubeId;

    if (seedSong.isFromJiosaavn) {
      youtubeId = await getVideoId(seedSong);
    } else {
      youtubeId = seedSong.id;
    }

    if (youtubeId == null) return [];

    // Tier 1: YouTube Music radio — the official automix.
    final radio = await getYtmRadio(youtubeId);
    if (radio.isNotEmpty) {
      final filtered = radio.where((s) => s.id != youtubeId).toList();
      if (filtered.isNotEmpty) return filtered;
      print('↳ YTM radio only contained the seed — next tier');
    }

    // Tier 2: yt_extractor related streams.
    try {
      await _ensureExtractorInit();
      final related = await _extractor
          .getRelatedStreams('https://www.youtube.com/watch?v=$youtubeId')
          .timeout(const Duration(seconds: 8));
      final songs = <Song>[];
      for (final item in related) {
        final vid = _extractVideoId(item.url);
        if (vid == null || vid == youtubeId) continue;
        songs.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/maxresdefault.jpg',
          duration: Duration(seconds: item.duration ?? 0),
        ));
      }
      if (songs.isNotEmpty) return songs;
      print('↳ related streams empty — falling back to search');
    } catch (e) {
      print('getRelatedStreams failed: $e');
    }

    // Tier 3: filtered music search fallback.
    try {
      await _ensureExtractorInit();
      final page = await _extractor
          .search(
        '${seedSong.title} ${seedSong.artist.split(',').first.trim()}',
        filter: SearchFilter.musicSongs,
      )
          .timeout(const Duration(seconds: 8));
      final artistPart = seedSong.artist.split(',').first.trim();
      final artistWords = artistPart.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toSet();

      final songs = <Song>[];
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid == null || vid == youtubeId) continue;
        final author = (item.uploaderName ?? '').toLowerCase();
        final title = item.name.toLowerCase();
        final artistMatch =
        artistWords.any((w) => w.length > 2 && author.contains(w));
        final seedTitleWords = seedSong.title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 3)
            .toList();
        final titleMatch = seedTitleWords.any((w) => title.contains(w));
        if (!artistMatch && !titleMatch) continue;

        songs.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/maxresdefault.jpg',
          duration: Duration(seconds: item.duration ?? 0),
        ));
        if (songs.length >= 20) break;
      }
      print('↳ related fallback (music search): ${songs.length} songs');
      return songs;
    } catch (e) {
      print('related fallback failed: $e');
      return [];
    }
  }

  String? _extractVideoId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v'];
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          (segments.contains('watch') ||
              segments.contains('embed') ||
              segments.contains('shorts'))) {
        return segments.last;
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _yt.close();
    _jiosaavn.dispose();
    _probe.close();
    _ytmClient.close();
  }
}

class _HdClient {
  final String name;
  final yt_explode.YoutubeApiClient client;
  final String? userAgent;
  const _HdClient(this.name, this.client, this.userAgent);
}

class _HlsVariant {
  final String url;
  final String label;
  const _HlsVariant(this.url, this.label);
}

typedef _JsonMap = Map<String, dynamic>;

extension _Read on _JsonMap {
  _JsonMap? getMap(String key) {
    final v = this[key];
    return v is Map ? _JsonMap.from(v) : null;
  }

  List<dynamic>? getList(String key) {
    final v = this[key];
    return v is List ? v : null;
  }

  T? getValue<T>(String key) {
    final v = this[key];
    return v is T ? v : null;
  }
}