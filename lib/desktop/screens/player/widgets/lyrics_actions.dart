// ZenMusic · the only control shown over the lyrics: the Sing (mic) button.
// Translation, style and animation live in Settings > Appearance > Lyrics.
import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/sing_mode.dart';

class LyricsActions extends StatelessWidget {
  const LyricsActions({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(4),
        child: SingButton(size: 22, color: Colors.white),
      );
}
