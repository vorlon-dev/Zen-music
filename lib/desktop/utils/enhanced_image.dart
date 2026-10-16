// ZenMusic Desktop — ported from Echo Music (GPL-3.0), utils/enhanced_image.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// DEVIATION (marked, bug-fix): Echo upgraded sizes via literal replaceAll of
// specific tokens (w60-h60, w226-h226, =s192...). Modern YTM thumbnail URLs
// use the "=w120-h120-p-k-no-nu" format, which NONE of those patterns match —
// observed as low-quality covers on Android. Rewritten with regex size
// normalization covering BOTH formats; sddefault fallbacks preserved.
// DEVIATION (marked, bug-fix #2): the "-c" crop flag is appended so the
// server returns an exact square (w == h) instead of fit-inside, which kept
// the source aspect ratio. Video thumbnails (i.ytimg.com) cannot be cropped
// via URL; crop those in the UI with AspectRatio(1) + BoxFit.cover.

String getEnhancedImage(String imageUrl,
    {String quality = 'high', double? width, double? dp}) {
  int? targetSize;
  if (width != null) {
    targetSize = ((dp ?? 1) * width).ceil();
  } else {
    switch (quality) {
      case 'high':
        targetSize = 500;
        break;
      case 'medium':
        targetSize = 300;
        break;
      case 'low':
        targetSize = 100;
        break;
      default:
        targetSize = null;
    }
  }

  String url = imageUrl.trim();

  if (targetSize != null) {
    // Modern format: ...=w120-h120-p-k-no-nu (suffix params dropped — they
    // are rendering hints only). "-c" asks the server for a centre-cropped
    // exact square instead of a fit-inside resize.
    url = url.replaceAll(
        RegExp(r'=w\d+-h\d+[a-z0-9-]*'), '=w$targetSize-h$targetSize-c');
    // Legacy formats: .../w60-h60/... and trailing w60-h60 tokens.
    // The lookbehind skips the "=w..-h.." token rewritten above.
    url = url.replaceAll(
        RegExp(r'(?<![=\w])w\d+-h\d+'), 'w$targetSize-h$targetSize');
    url = url.replaceAll('sddefault', 'mqdefault');
    return url;
  }

  // Unspecified quality: only the sddefault upgrade, verbatim upstream.
  return url.replaceAll('sddefault', 'maxresdefault');
}