import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../main.dart';
import '../screens/video_watch_screen.dart';

/// Handles YouTube links shared into the app via the Android share
/// sheet. Opens the dedicated video watch page for the shared video.
class ShareIntentService {
  ShareIntentService._();
  static final ShareIntentService instance = ShareIntentService._();

  static final RegExp _ytVideo = RegExp(
      r'(?:youtu\.be\/|watch\?v=|shorts\/|embed\/)([A-Za-z0-9_-]{11})');

  StreamSubscription? _sub;
  NavigatorState? _navigator;
  bool _initialized = false;

  /// Call once from the root widget after the first frame.
  void init(NavigatorState navigator) {
    if (_initialized) return;
    _initialized = true;
    _navigator = navigator;

    // App opened fresh via a shared link (cold start).
    ReceiveSharingIntent.instance.getInitialMedia().then((media) {
      _handle(media);
      ReceiveSharingIntent.instance.reset();
    }).catchError((_) {});

    // Link shared while the app is running (warm).
    _sub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handle, onError: (_) {});
  }

  void _handle(List<SharedMediaFile> media) {
    final nav = _navigator;
    if (nav == null || !nav.mounted) return;

    for (final item in media) {
      // Shared text arrives in `path` for plain-text shares.
      final text = item.path;
      final m = _ytVideo.firstMatch(text);
      if (m == null) continue;
      final videoId = m.group(1)!;

      // The watch page plays the video's own audio — pause the music
      // queue so the two don't overlap.
      audioHandler.pause();

      nav.push(
        MaterialPageRoute(
          builder: (_) => VideoWatchScreen(videoId: videoId),
        ),
      );
      return; // one video per share
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}