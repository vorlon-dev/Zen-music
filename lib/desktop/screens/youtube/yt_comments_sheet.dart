// ZenMusic · vorlon-dev

// VideoClient.comments is marked @Deprecated upstream ("will not be
// supported anymore") but it is the ONLY comments API this vendored 3.1.0
// fork ships and it is fully functional — the deprecation guards against
// the upstream web-client removal, not a dead endpoint here.
// ignore_for_file: deprecated_member_use

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yexp;

import 'package:zenmusic/desktop/services/yt_audio_stream.dart' show ytExplode;

/// Same accent as yt_ui.kYtRed — duplicated (not imported) so the sheet
/// never pulls the UI kit into the watch page import graph.
const Color _kYtRed = Color(0xFFFF0033);

class YtCommentsSheet {
  YtCommentsSheet._();

  static void show(BuildContext context, String videoId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CommentsSheetBody(videoId: videoId),
    );
  }
}

class _CommentsSheetBody extends StatefulWidget {
  const _CommentsSheetBody({required this.videoId});
  final String videoId;

  @override
  State<_CommentsSheetBody> createState() => _CommentsSheetBodyState();
}

class _CommentsSheetBodyState extends State<_CommentsSheetBody> {
  yexp.CommentsList? _list;
  final List<yexp.Comment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  Object? _error;

  // Per-comment expanded replies.
  final Map<int, List<yexp.Comment>> _replies = {};
  final Map<int, bool> _repliesLoading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _comments.clear();
      _list = null;
      _exhausted = false;
    });
    try {
      final video = await ytExplode.videos.get(widget.videoId);
      final list = await ytExplode.videos.comments.getComments(video);
      if (!mounted) return;
      setState(() {
        _list = list;
        if (list != null) _comments.addAll(list);
        _exhausted = list == null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final list = _list;
    if (_loadingMore || list == null || _exhausted) return;
    setState(() => _loadingMore = true);
    try {
      final next = await list.nextPage();
      if (!mounted) return;
      setState(() {
        if (next == null) {
          _exhausted = true;
          _list = null;
        } else {
          _list = next;
          _comments.addAll(next);
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleReplies(int index) async {
    final comment = _comments[index];
    if (_replies.containsKey(index)) {
      setState(() => _replies.remove(index));
      return;
    }
    if (comment.replyCount <= 0) return;
    // No @internal continuation poking here — getReplies() itself returns
    // null when the comment carries no continuation token.
    setState(() => _repliesLoading[index] = true);
    try {
      final replies = await ytExplode.videos.comments.getReplies(comment);
      if (!mounted) return;
      setState(() {
        _replies[index] = replies == null ? const [] : replies.toList();
        _repliesLoading.remove(index);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _repliesLoading.remove(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 16),
              Text('Comments'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Close'.tr,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: _body(context, cs)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ColorScheme cs) {
    if (_loading) {
      return const Center(
          child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return YtCommentsError(
        message: 'Comments are not reachable right now.',
        onRetry: _load,
      );
    }
    if (_comments.isEmpty) {
      return Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Comments are turned off for this video.'.tr,
                  textAlign: TextAlign.center)));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 500) _loadMore();
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        itemCount: _comments.length + (_exhausted ? 0 : 1),
        itemBuilder: (context, i) {
          if (i >= _comments.length) {
            return const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          return _commentTile(i, _comments[i], cs, isReply: false);
        },
      ),
    );
  }

  Widget _commentTile(int index, yexp.Comment c, ColorScheme cs,
      {required bool isReply}) {
    final replies = _replies[index];
    final repliesLoading = _repliesLoading[index] == true;
    final authorInitial = c.author.isEmpty
        ? '?'
        : c.author.characters.first.toUpperCase();
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 44 : 14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isReply ? 11 : 14,
                backgroundColor: cs.primaryContainer,
                child: Text(authorInitial,
                    style: TextStyle(
                        fontSize: isReply ? 9 : 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.author}${c.publishedTime.isEmpty ? '' : '  ·  ${c.publishedTime}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Text(c.text,
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_alt_outlined,
                            size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${c.likeCount}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        if (c.isHearted) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.favorite,
                              size: 11, color: _kYtRed),
                        ],
                        const Spacer(),
                        if (!isReply && c.replyCount > 0)
                          TextButton(
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6)),
                            onPressed:
                                repliesLoading ? null : () => _toggleReplies(index),
                            child: Text(
                              replies != null
                                  ? 'Hide replies'
                                  : '${c.replyCount} ${c.replyCount == 1 ? 'reply' : 'replies'}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary),
                            ),
                          ),
                      ],
                    ),
                    if (repliesLoading)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (replies != null)
                      Column(
                        children: [
                          for (var i = 0; i < replies.length; i++)
                            _commentTile(index, replies[i], cs,
                                isReply: true),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Local error card so the sheet does not have to import the UI kit
/// (avoids a circular import with the watch page).
class YtCommentsError extends StatelessWidget {
  const YtCommentsError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 38, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Retry'.tr),
            ),
          ],
        ],
      ),
    );
  }
}
