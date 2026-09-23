import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/extension_feed_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/extension_feed_view.dart';
import '../widgets/wave_spinner.dart';

/// Detail page for an extension album / playlist / artist: header,
/// play-all, track list (album/playlist) or shelves (artist).
class ExtensionDetailScreen extends StatefulWidget {
  const ExtensionDetailScreen({
    super.key,
    required this.media,
    required this.onTrackTap,
    required this.onMediaTap,
  });

  final ExtMedia media;
  final void Function(List<ExtMedia> tracks, int index) onTrackTap;
  final void Function(ExtMedia media) onMediaTap;

  @override
  State<ExtensionDetailScreen> createState() => _ExtensionDetailScreenState();
}

class _ExtensionDetailScreenState extends State<ExtensionDetailScreen> {
  final _service = ExtensionFeedService();
  ExtDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.loadDetail(
        Map<String, dynamic>.from(widget.media.raw),
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is PlatformException && e.message != null
          ? e.message!
          : 'Could not load this page';
      setState(() {
        _loading = false;
        _error = message;
      });
    }
  }

  ExtMedia get _headerMedia => _detail?.item ?? widget.media;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: WaveSpinner(size: 26))
            : _error != null
            ? _errorView()
            : ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _header(),
            if (_detail!.tracks.isEmpty && _detail!.shelves.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No tracks found in this page',
                    style: TextStyle(
                      color: SpotifyColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            if (_detail!.tracks.isNotEmpty) ...[
              _playAllButton(),
              _trackList(),
            ],
            if (_detail!.shelves.isNotEmpty)
              ExtensionShelfList(
                shelves: _detail!.shelves,
                onTrackTap: widget.onTrackTap,
                onMediaTap: widget.onMediaTap,
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: SpotifyColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SpotifyColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _header() {
    final media = _headerMedia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BackButton(color: SpotifyColors.textPrimary),
            const Spacer(),
          ],
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ExtCover(
              url: media.coverUrl,
              headers: media.coverHeaders,
              hex: media.coverHex,
              size: 190,
              borderRadius: 14,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                media.kind.toUpperCase(),
                style: const TextStyle(
                  color: SpotifyColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                media.title,
                style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              if ((media.subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  media.subtitle!,
                  style: const TextStyle(
                    color: SpotifyColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _playAllButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Material(
        color: SpotifyColors.green,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => widget.onTrackTap(_detail!.tracks, 0),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded,
                    color: Colors.black, size: 26),
                const SizedBox(width: 6),
                Text(
                  'Play ${_detail!.tracks.length} tracks',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackList() {
    final tracks = _detail!.tracks;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < tracks.length; i++)
            ExtTrackRow(
              index: i + 1,
              track: tracks[i],
              onTap: () => widget.onTrackTap(tracks, i),
            ),
        ],
      ),
    );
  }
}