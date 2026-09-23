import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

/// Shimmering placeholder block. The base primitive: wrap any
/// [SkeletonBox]/[SkeletonTile]/[SkeletonShelf] layout in these.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1400),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = SpotifyColors.surface;
    final highlight = SpotifyColors.surfaceLight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweep a highlight gradient left→right, looping.
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + 2.4 * t, 0),
              end: Alignment(-0.2 + 2.4 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Horizontal shelf placeholder: circle/round tiles like song shelves.
class SkeletonShelf extends StatelessWidget {
  const SkeletonShelf({super.key, this.itemCount = 4, this.square = true});

  final int itemCount;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Skeleton(width: 140, height: 16, borderRadius: 6),
        ),
        SizedBox(
          height: square ? 180 : 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(
                  width: square ? 140 : 160,
                  height: square ? 140 : 160,
                  borderRadius: 10,
                ),
                const SizedBox(height: 8),
                Skeleton(width: square ? 120 : 140, height: 12, borderRadius: 6),
                const SizedBox(height: 4),
                Skeleton(width: 80, height: 10, borderRadius: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Wide card placeholder for collection rows.
class SkeletonCollectionCard extends StatelessWidget {
  const SkeletonCollectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Skeleton(width: 160, height: 160, borderRadius: 10),
        SizedBox(height: 8),
        Skeleton(width: 120, height: 12, borderRadius: 6),
        SizedBox(height: 4),
        Skeleton(width: 90, height: 10, borderRadius: 6),
      ],
    );
  }
}

/// Row placeholder for search results / list items.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: const [
          Skeleton(width: 52, height: 52, borderRadius: 8),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(height: 13, borderRadius: 6),
                SizedBox(height: 6),
                Skeleton(width: 120, height: 11, borderRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}