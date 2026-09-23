import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';
import 'queue_list_view.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SpotifyColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: const QueueListView(isBottomSheet: true),
    );
  }
}