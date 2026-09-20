import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoBackground extends StatefulWidget {
  final String videoUrl;
  final Stream<Duration> positionStream;
  final Stream<bool> playingStream;

  const VideoBackground({
    super.key,
    required this.videoUrl,
    required this.positionStream,
    required this.playingStream,
  });

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;

  @override
  void initState() {
    super.initState();
    _init();
    _posSub = widget.positionStream.listen(_syncPosition);
    _playSub = widget.playingStream.listen(_syncPlaying);
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(false);

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initialized = true;
      });
    } catch (e) {
      print('VideoBackground init failed: $e');
    }
  }

  void _syncPosition(Duration audioPos) {
    final video = _controller;
    if (video == null || !_initialized) return;

    final drift = (video.value.position - audioPos).abs();
    if (drift > const Duration(milliseconds: 500)) {
      video.seekTo(audioPos);
    }
  }

  void _syncPlaying(bool playing) {
    final video = _controller;
    if (video == null || !_initialized) return;

    if (playing) {
      video.play();
    } else {
      video.pause();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}