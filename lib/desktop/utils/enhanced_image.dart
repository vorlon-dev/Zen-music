// ZenMusic · vorlon-dev



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
