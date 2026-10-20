// ZenMusic Desktop — ported from Echo Music (GPL-3.0), screens/search/search_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// REDESIGN: quieter, theme-driven layout. Fluent System Icons throughout.
// Colors come from Theme.of(context).colorScheme so it follows the app theme.
// Behaviour (cubit, playback, routing, suggestion overlay) is unchanged.
//
// pubspec.yaml:  fluentui_system_icons: ^1.1.273   (use the latest on pub.dev)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:zenmusic/desktop/screens/search/cubit/search_cubit.dart';
// NOTE: adjust this path if your VideoWatchPage lives elsewhere.
import 'package:zenmusic/desktop/screens/video/video_watch_page.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/internet_guard.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

const double _kContentWidth = 960;

class SearchPage extends StatelessWidget {
  const SearchPage({super.key, this.endpoint, this.isMore = false});
  final Map<String, dynamic>? endpoint;
  final bool isMore;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(GetIt.I<YTMusic>(), endpoint: endpoint),
      child: _SearchPage(title: endpoint?['query'], isMore: isMore),
    );
  }
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({this.title, this.isMore = false});
  final String? title;
  final bool isMore;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  late final ScrollController _scrollController;
  TextEditingController? _textEditingController;
  FocusNode? _focusNode;
  SearchFilter _filter = SearchFilter.all;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _focusNode?.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollListener() async {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 120) {
      await context.read<SearchCubit>().fetchNext();
    }
  }

  Future<void> onSubmit(String query) async {
    if (query.trim().isEmpty) return;
    _focusNode?.unfocus();
    await context.read<SearchCubit>().search(query);
  }

  void _pickFilter(SearchFilter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    context.read<SearchCubit>().setFilter(f);
  }

  @override
  Widget build(BuildContext context) {
    return InternetGuard(
      onInternetLost: () => _focusNode?.unfocus(),
      onInternetRestored: () {
        if (widget.title != null) {
          context.read<SearchCubit>().search('');
        } else {
          _focusNode?.requestFocus();
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const AdaptiveAppBar().preferredSize,
          child: LayoutBuilder(builder: (context, constraints) {
            return AdaptiveAppBar(
              title: widget.title != null
                  ? Text(widget.title!)
                  : Material(
                color: Colors.transparent,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SearchSuggestField(
                      onSubmit: onSubmit,
                      onPick: onSubmit,
                      onControllerReady: (c) => _textEditingController = c,
                    ),
                  ),
                ),
              ),
              automaticallyImplyLeading: constraints.maxWidth > 400,
            );
          }),
        ),
        body: Column(
          children: [
            if (widget.title == null)
              _FilterTabs(selected: _filter, onChanged: _pickFilter),
            Expanded(
              child: BlocBuilder<SearchCubit, SearchState>(
                builder: (context, state) {
                  switch (state) {
                    case SearchLoading():
                      return const Center(child: ExpressiveLoadingIndicator());
                    case SearchError():
                      return _Notice(
                        icon: FluentIcons.error_circle_24_regular,
                        title: 'Search failed',
                        body: (state.message?.isNotEmpty ?? false)
                            ? state.message!
                            : 'Check your connection and try again.',
                      );
                    case SearchSuccess():
                      if (state.sections.isEmpty) {
                        return const _Notice(
                          icon: FluentIcons.search_24_regular,
                          title: 'Search for music',
                          body: 'Songs, albums, artists, playlists and videos.',
                        );
                      }
                      return SingleChildScrollView(
                        controller: _scrollController,
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                            const BoxConstraints(maxWidth: _kContentWidth),
                            child: Padding(
                              padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 32),
                              child: Column(
                                children: [
                                  for (final s in state.sections)
                                    _SectionBlock(
                                        section: s, isMore: widget.isMore),
                                  if (state.loadingMore)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                          child: ExpressiveLoadingIndicator()),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter tabs: plain text with an underline, not pills.
// ---------------------------------------------------------------------------

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.selected, required this.onChanged});
  final SearchFilter selected;
  final ValueChanged<SearchFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tab(String label, IconData off, IconData on, SearchFilter f) {
      final sel = selected == f;
      final color = sel ? cs.onSurface : cs.onSurfaceVariant;
      return InkWell(
        onTap: () => onChanged(f),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sel ? on : off, size: 20, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 2,
                width: sel ? 28 : 0,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kContentWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tab('All', FluentIcons.search_24_regular,
                    FluentIcons.search_24_filled, SearchFilter.all),
                const SizedBox(width: 12),
                tab('Videos', FluentIcons.video_clip_24_regular,
                    FluentIcons.video_clip_24_filled, SearchFilter.videos),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, this.isMore = false});
  final Map<String, dynamic> section;
  final bool isMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contents = (section['contents'] as List?) ?? const [];
    final hasTitle = section['title'] != null && !isMore;
    final trailingText = section['trailing']?['text'];

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      section['title'],
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2),
                    ),
                  ),
                  if (trailingText != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                        visualDensity: VisualDensity.compact,
                      ),
                      iconAlignment: IconAlignment.end,
                      onPressed: () => context.push('/search', extra: {
                        'endpoint': section['trailing']['endpoint'],
                        'isMore': true,
                      }),
                      icon: const Icon(FluentIcons.chevron_right_24_regular,
                          size: 16),
                      label: Text(trailingText,
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
          for (final e in contents.asMap().entries)
            if ((e.value as Map)['isYtVideo'] == true)
              _VideoCard(item: e.value as Map)
            else
              _ResultTile(item: e.value as Map, section: contents, index: e.key),
        ],
      ),
    );
  }
}

/// YouTube video: 16:9 thumbnail, duration badge, title, channel.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.item});
  final Map item;

  void _watch(BuildContext context) {
    final id = item['videoId'].toString();
    if (Platform.isAndroid) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoWatchPage(videoId: id)));
    } else {
      // Desktop has no native video extraction: play the audio instead.
      GetIt.I<MediaPlayer>().playSong(Map.from(item));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thumb = (item['thumbnails'] as List?)?.isNotEmpty == true
        ? item['thumbnails'].last['url'] as String
        : null;
    final duration = item['duration']?.toString() ?? '';
    final live = duration == 'LIVE';
    final channel = (item['artist'] ?? '').toString();
    final subtitle = (item['subtitle'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _watch(context),
        onLongPress: () => Modals.showSongBottomModal(context, item),
        onSecondaryTap: () => Modals.showSongBottomModal(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: cs.surfaceContainerHighest),
                    _YtThumb(
                      videoId: item['videoId']?.toString(),
                      fallbackUrl: thumb,
                    ),
                    if (duration.isNotEmpty)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: live
                                ? const Color(0xFFC62828)
                                : Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            duration,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 0, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.3),
                        ),
                        if (subtitle.isNotEmpty || channel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              subtitle.isNotEmpty ? subtitle : channel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Play as audio',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(FluentIcons.headphones_24_regular,
                        size: 22, color: cs.onSurfaceVariant),
                    onPressed: () =>
                        GetIt.I<MediaPlayer>().playSong(Map.from(item)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.item,
    required this.section,
    required this.index,
  });
  final Map item;
  final List section;
  final int index;

  bool get _isTrack => item['videoId'] != null;

  void _openMenu(BuildContext context) {
    if (_isTrack) {
      Modals.showSongBottomModal(context, item);
    } else if (item['endpoint'] != null) {
      Modals.showPlaylistBottomModal(context, item);
    }
  }

  Future<void> _open(BuildContext context) async {
    if (_isTrack) {
      // JioSaavn and Spotify rows enter the section queue; YT keeps the
      // single-song + autofetch behavior.
      final isSpotify = (item['spotifyUri'] as String?)?.isNotEmpty == true;
      final isJioSaavn =
          (item['jiosaavnStreamUrl'] as String?)?.isNotEmpty == true;
      if (isSpotify || isJioSaavn) {
        await GetIt.I<MediaPlayer>().playFromSection(
          List<Map<String, dynamic>>.from(section),
          index,
        );
      } else {
        await GetIt.I<MediaPlayer>().playSong(Map.from(item));
      }
    } else if (item['endpoint'] != null) {
      context.push('/browse', extra: {'endpoint': item['endpoint']});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final round = ['ARTIST', 'PROFILE'].contains(item['type']);
    final hasThumb =
        item['thumbnails'] != null && item['thumbnails'].isNotEmpty;

    return AdaptiveListTile(
      onTap: () => _open(context),
      onLongPress: () => _openMenu(context),
      onSecondaryTap: () => _openMenu(context),
      dense: false,
      title: Text(
        item['title'] ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: item['subtitle'] != null
          ? Text(
        item['subtitle'],
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurfaceVariant),
      )
          : null,
      leading: hasThumb
          ? ClipRRect(
        borderRadius: BorderRadius.circular(round ? 28 : 6),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Image.network(
            _hiRes(item['thumbnails'].last['url'].toString(), 300),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Icon(FluentIcons.music_note_2_24_regular,
                  color: cs.onSurfaceVariant),
            ),
          ),
        ),
      )
          : null,
      trailing: !_isTrack && item['endpoint'] != null
          ? Icon(FluentIcons.chevron_right_24_regular,
          size: 20, color: cs.onSurfaceVariant)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Search field + suggestions (in-tree replacement for flutter_typeahead).
// The panel sits in a TextFieldTapRegion so a mouse-down on a suggestion
// does not unfocus the field before the tap completes.
// ---------------------------------------------------------------------------

class SearchSuggestField extends StatefulWidget {
  const SearchSuggestField({
    super.key,
    required this.onSubmit,
    required this.onPick,
    this.onControllerReady,
  });

  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onPick;
  final ValueChanged<TextEditingController>? onControllerReady;

  @override
  State<SearchSuggestField> createState() => _SearchSuggestFieldState();
}

class _SearchSuggestFieldState extends State<SearchSuggestField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final ScrollController _scrollController = ScrollController();
  OverlayEntry? _overlay;
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.onControllerReady?.call(_controller);
    _controller.addListener(() => setState(() {})); // toggles clear button
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_focusNode.hasFocus) _hideOverlay();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideOverlay();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay() {
    if (_overlay != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlay = OverlayEntry(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _hideOverlay,
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              showWhenUnlinked: false,
              offset: const Offset(0, 6),
              child: TextFieldTapRegion(
                child: Material(
                  color: cs.surfaceContainerHigh,
                  elevation: 6,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints:
                    const BoxConstraints(maxWidth: 420, maxHeight: 340),
                    child: _buildSuggestionsList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
    overlay.insert(_overlay!);
  }

  Future<void> _fetch(String query) async {
    final cubit = context.read<SearchCubit>();
    setState(() => _loading = true);
    try {
      final results = await cubit.getSuggestions(query);
      if (!mounted || !_focusNode.hasFocus) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
      _overlay?.markNeedsBuild();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _overlay?.markNeedsBuild();
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(query));
  }

  void _runPicked(void Function() action) {
    action();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hideOverlay();
        _focusNode.unfocus();
      }
    });
  }

  Widget _buildSuggestionsList() {
    if (_loading && _suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_suggestions.isEmpty) {
      return const SizedBox(height: 8, width: 420);
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final item = _suggestions[index];
        if (item['type'] == 'TEXT') {
          final query = item['query']?.toString() ?? '';
          final isHistory = item['isHistory'] != null;
          return AdaptiveListTile(
            dense: true,
            leading: Icon(
              isHistory
                  ? FluentIcons.history_24_regular
                  : FluentIcons.search_24_regular,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Edit search',
              visualDensity: VisualDensity.compact,
              icon: Icon(FluentIcons.arrow_up_left_24_regular,
                  size: 18, color: cs.onSurfaceVariant),
              onPressed: () {
                _controller.value = TextEditingValue(
                  text: query,
                  selection: TextSelection.collapsed(offset: query.length),
                );
                _fetch(query);
              },
            ),
            onTap: () => _runPicked(() {
              _controller.text = query;
              widget.onPick(query);
            }),
          );
        }
        final videoId = item['videoId']?.toString();
        return AdaptiveListTile(
          dense: true,
          leading: (item['thumbnails'] as List?)?.isNotEmpty == true
              ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Image.network(
                item['thumbnails'].first['url'] ?? '',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                const SizedBox(width: 40, height: 40),
              ),
            ),
          )
              : null,
          title: Text(item['title'] ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: item['subtitle'] != null
              ? Text(item['subtitle'],
              maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          onTap: () {
            if (videoId != null && videoId.isNotEmpty) {
              _runPicked(() => GetIt.I<MediaPlayer>().playSong(Map.from(item)));
            } else if (item['endpoint'] != null) {
              final endpoint = item['endpoint'];
              _runPicked(() =>
                  context.push('/browse', extra: {'endpoint': endpoint}));
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _layerLink,
      child: AdaptiveTextField(
        focusNode: _focusNode,
        controller: _controller,
        onChanged: _onChanged,
        onSubmitted: (q) => _runPicked(() => widget.onSubmit(q)),
        keyboardType: TextInputType.text,
        maxLines: 1,
        autofocus: true,
        textInputAction: TextInputAction.search,
        fillColor: cs.surfaceContainerHighest,
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        borderRadius: BorderRadius.circular(28),
        hintText: 'Search songs, artists, videos',
        prefix: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(FluentIcons.search_24_regular,
              size: 20, color: cs.onSurfaceVariant),
        ),
        suffix: _controller.text.isEmpty
            ? null
            : GestureDetector(
          onTap: () {
            _controller.clear();
            setState(() => _suggestions = []);
            _overlay?.markNeedsBuild();
          },
          child: Icon(FluentIcons.dismiss_circle_24_filled,
              size: 20, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Thumbnail quality
// ---------------------------------------------------------------------------

/// Upgrades Google-hosted (YT Music / lh3) thumbnail URLs to [size] px.
String _hiRes(String url, [int size = 300]) {
  final re = RegExp(r'=w\d+-h\d+');
  if (re.hasMatch(url)) return url.replaceFirst(re, '=w$size-h$size-l90-rj');
  final s = RegExp(r'=s\d+');
  if (s.hasMatch(url)) return url.replaceFirst(s, '=s$size');
  return url;
}

/// Best YouTube thumbnail: tries maxres (1280x720), then 720p, 640x480,
/// 480x360, then whatever URL the search returned.
class _YtThumb extends StatefulWidget {
  const _YtThumb({required this.videoId, this.fallbackUrl});
  final String? videoId;
  final String? fallbackUrl;

  @override
  State<_YtThumb> createState() => _YtThumbState();
}

class _YtThumbState extends State<_YtThumb> {
  late final List<String> _urls = [
    if (widget.videoId != null && widget.videoId!.length == 11)
      for (final q in ['maxresdefault', 'hq720', 'sddefault', 'hqdefault'])
        'https://i.ytimg.com/vi/${widget.videoId}/$q.jpg',
    if (widget.fallbackUrl != null) widget.fallbackUrl!,
  ];
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_i >= _urls.length) {
      return Icon(FluentIcons.play_circle_24_regular,
          size: 40, color: cs.onSurfaceVariant);
    }
    return Image.network(
      _urls[_i],
      key: ValueKey(_urls[_i]),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _i++);
        });
        return const SizedBox.shrink();
      },
    );
  }
}