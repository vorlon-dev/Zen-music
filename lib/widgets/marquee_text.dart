import 'package:flutter/material.dart';

import 'marquee.dart';

class MarqueeText extends StatelessWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.backDuration = const Duration(seconds: 1),
  });

  final String text;
  final TextStyle style;
  final Duration backDuration;

  @override
  Widget build(BuildContext context) {
    return MarqueeWidget(
      backDuration: backDuration,
      child: Text(text, style: style, maxLines: 1),
    );
  }
}