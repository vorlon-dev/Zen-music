// ZenMusic Desktop — ported from Echo Music (GPL-3.0), screens/search/search_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// PORT DEVIATIONS: sl() -> GetIt.I<YTMusic>(); l10n -> 'Search'; TypeAheadField
// REPLACED with in-tree SearchSuggestField (flutter_typeahead pulls the
// android-31 keyboard plugin). SUGGESTION TAP CONTRACT: the outside-tap
// catcher is the PARENT of the panel — deepest recognizer wins, so item taps
// fire and outside taps close. Teardown defers to after the frame.
//
// FIX: the suggestion panel is wrapped in TextFieldTapRegion so a mouse-down
// on a suggestion no longer unfocuses the text field (which was removing the
// overlay before the tap could complete). The focus-lost hide is also delayed
// slightly as a safety net.

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:zenmusic/desktop/screens/search/cubit/search_cubit.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/internet_guard.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key, this.endpoint, this.isMore = false});
  final Map<String, dynamic>? endpoint;
  final bool isMore;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(GetIt.I<YTMusic>(), endpoint: endpoint),
      child: _SearchPage(
        title: endpoint?['query'],
        isMore: isMore,
      ),
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
  late ScrollController _scrollController;
  TextEditingController? _textEditingController;
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    _focusNode?.requestFocus();
  }

  Future<void> _scrollListener() async {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      await context.read<SearchCubit>().fetchNext();
    }
  }

  Future<void> onSubmit(String query) async {
    if (query.trim() == '') return;
    _focusNode?.unfocus();
    await context.read<SearchCubit>().search(query);
  }

  @override
  Widget build(BuildContext context) {
    return InternetGuard(
      onInternetLost: () {
        _focusNode?.unfocus();
      },
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
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                          const BoxConstraints(maxWidth: 350),
                          child: SearchSuggestField(
                            onSubmit: onSubmit,
                            onPick: onSubmit,
                            onControllerReady: (ctrl) {
                              _textEditingController = ctrl;
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              automaticallyImplyLeading:
              (constraints.maxWidth <= 400) ? false : true,
            );
          }),
        ),
        body: BlocBuilder<SearchCubit, SearchState>(
          builder: (context, state) {
            switch (state) {
              case SearchLoading():
                return const SizedBox();
              case SearchError():
                return Center(
                  child: Text(state.message ?? ''),
                );
              case SearchSuccess():
                return SingleChildScrollView(
                  controller: _scrollController,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          ...state.sections.map((section) {
                            if (Platform.isWindows) {
                              return Center(
                                child: Adaptivecard(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _SearchSectionItem(
                                      section: section, isMore: widget.isMore),
                                ),
                              );
                            }
                            return _SearchSectionItem(
                                section: section, isMore: widget.isMore);
                          }),
                          if (state.loadingMore)
                            const Center(child: ExpressiveLoadingIndicator())
                        ],
                      ),
                    ),
                  ),
                );
            }
          },
        ),
      ),
    );
  }
}

class _SearchSectionItem extends StatelessWidget {
  const _SearchSectionItem({required this.section, this.isMore = false});
  final Map<String, dynamic> section;
  final bool isMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (section['title'] != null && !isMore)
          AdaptiveListTile(
            contentPadding:
            const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            title: Text(
              section['title'],
              style:
              const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            trailing: section['trailing']?['text'] != null
                ? Padding(
              padding: EdgeInsets.symmetric(
                  vertical: Platform.isAndroid ? 12 : 0),
              child: AdaptiveOutlinedButton(
                  onPressed: () {
                    context.push(
                      '/search',
                      extra: {
                        'endpoint': section['trailing']['endpoint'],
                        'isMore': true,
                      },
                    );
                  },
                  child: Text(
                    section['trailing']['text'],
                    style: const TextStyle(fontSize: 12),
                  )),
            )
                : null,
          ),
        ...section['contents'].map((item) {
          return _SearchListTile(item: item);
        })
      ],
    );
  }
}

class _SearchListTile extends StatelessWidget {
  const _SearchListTile({
    required this.item,
  });
  final Map item;
  @override
  Widget build(BuildContext context) {
    return AdaptiveListTile(
      onSecondaryTap: () {
        if (item['videoId'] != null) {
          Modals.showSongBottomModal(context, item);
        } else if (item['endpoint'] != null) {
          Modals.showPlaylistBottomModal(context, item);
        }
      },
      onTap: () async {
        if (item['videoId'] != null) {
          await GetIt.I<MediaPlayer>().playSong(Map.from(item));
        } else if (item['endpoint'] != null && item['videoId'] == null) {
          context.push(
            '/browse',
            extra: {
              'endpoint': item['endpoint'],
            },
          );
        }
      },
      onLongPress: () {
        if (item['videoId'] != null) {
          Modals.showSongBottomModal(context, item);
        } else if (item['endpoint'] != null) {
          Modals.showPlaylistBottomModal(context, item);
        }
      },
      dense: false,
      title: Text(
        item['title'],
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item['subtitle'] != null
          ? Text(
        item['subtitle'],
        maxLines: 1,
        style: TextStyle(color: Colors.grey.withValues(alpha: 0.9)),
        overflow: TextOverflow.ellipsis,
      )
          : null,
      leading: item['thumbnails'] != null && item['thumbnails'].isNotEmpty
          ? ClipRRect(
          borderRadius: BorderRadius.circular(
              ['ARTIST', 'PROFILE'].contains(item['type']) ? 30 : 3),
          child: Image.network(
            item['thumbnails'].first['url'],
            width: 50,
          ))
          : null,
      trailing: item['videoId'] == null && item['endpoint'] != null
          ? const Icon(CupertinoIcons.chevron_right)
          : null,
    );
  }
}

/// In-tree replacement for flutter_typeahead (deviation, see header).
/// TAP CONTRACT: the outside-tap catcher is the PARENT of the suggestion
/// panel — the deepest recognizer (the tapped item) always beats the parent
/// catcher in the gesture arena, so item taps fire and outside taps close.
/// Picked actions run FIRST; overlay teardown defers to after the frame.
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
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        // Give a pending tap on a suggestion time to complete before
        // tearing the overlay down.
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_focusNode.hasFocus) _hideOverlay();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Remove the overlay BEFORE disposing the things it references.
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
      // Panel nested INSIDE the catcher: taps on items are claimed by the
      // item's own recognizer (deepest wins the arena), taps anywhere else
      // bubble up to the catcher and close. No sibling arena fight.
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
              offset: const Offset(0, 8),
              // TextFieldTapRegion: taps inside the panel count as "inside"
              // the text field, so the field does NOT unfocus on mouse-down.
              child: TextFieldTapRegion(
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints:
                    const BoxConstraints(maxWidth: 350, maxHeight: 320),
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
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetch(query);
    });
  }

  /// Runs the picked action FIRST, then tears the overlay down after the
  /// frame — teardown inside the tap callback was killing follow-through.
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
      return const SizedBox(height: 8, width: 350);
    }
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final item = _suggestions[index];
        if (item['type'] == 'TEXT') {
          final query = item['query']?.toString() ?? '';
          return AdaptiveListTile(
            dense: true,
            leading: item['isHistory'] != null
                ? const Icon(Icons.history, size: 20)
                : null,
            title: Text(query),
            onTap: () {
              _runPicked(() {
                _controller.text = query;
                widget.onPick(query);
              });
            },
          );
        }
        final videoId = item['videoId']?.toString();
        return AdaptiveListTile(
          dense: true,
          leading: (item['thumbnails'] as List?)?.isNotEmpty == true
              ? ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.network(
              item['thumbnails'].first['url'] ?? '',
              width: 40,
              errorBuilder: (_, __, ___) =>
              const SizedBox(width: 40, height: 40),
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
              _runPicked(() {
                GetIt.I<MediaPlayer>().playSong(Map.from(item));
              });
            } else if (item['endpoint'] != null) {
              final endpoint = item['endpoint'];
              _runPicked(() {
                context.push('/browse', extra: {'endpoint': endpoint});
              });
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: AdaptiveTextField(
        focusNode: _focusNode,
        controller: _controller,
        onChanged: _onChanged,
        onSubmitted: (q) {
          _runPicked(() => widget.onSubmit(q));
        },
        keyboardType: TextInputType.text,
        maxLines: 1,
        autofocus: true,
        textInputAction: TextInputAction.search,
        fillColor: Colors.grey.withValues(alpha: 0.3),
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        borderRadius: BorderRadius.circular(35),
        hintText: 'Search',
        suffix: GestureDetector(
          onTap: () {
            setState(() {
              _controller.clear();
              _suggestions = [];
              _overlay?.markNeedsBuild();
            });
          },
          child: const Icon(CupertinoIcons.clear),
        ),
      ),
    );
  }
}