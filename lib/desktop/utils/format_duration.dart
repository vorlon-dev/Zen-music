// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.

/// Formats [duration] as a clock-style string.
///
/// - Under an hour: `m:ss` (for example `0:05`, `3:05`, `59:59`).
/// - An hour or more: `h:mm:ss` (for example `1:00:05`).
///
/// Negative durations are treated as zero.
String formatDuration(Duration duration) {
  final Duration safe = duration.isNegative ? Duration.zero : duration;

  String twoDigits(int n) => n.toString().padLeft(2, '0');

  final int hours = safe.inHours;
  final int minutes = safe.inMinutes.remainder(60);
  final String seconds = twoDigits(safe.inSeconds.remainder(60));

  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:$seconds';
  }
  return '$minutes:$seconds';
}
