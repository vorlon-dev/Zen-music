#!/usr/bin/env bash
# Same as cleanup_unused.ps1 for macOS/Linux/Git-Bash. Dry run by default; pass --apply.
set -u
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
CANDIDATES=(
  "lib/desktop/liquid/pipeline_warmup.dart"
  "lib/desktop/lossless/lossless_prefs.dart"
  "lib/desktop/screens/settings/widgets/color_icon.dart"
  "lib/desktop/screens/stubs.dart"
  "lib/desktop/screens/youtube/youtube_page.dart"
  "lib/desktop/screens/youtube/yt_comments_sheet.dart"
  "lib/desktop/screens/youtube/yt_home_page.dart"
  "lib/desktop/screens/youtube/yt_shorts_feed.dart"
  "lib/desktop/services/listen_together_service.dart"
  "lib/desktop/services/update_service/models/update_info.dart"
  "lib/desktop/services/update_service/update_service.dart"
  "lib/desktop/services/update_service/widgets/update_checking_dialog.dart"
  "lib/desktop/services/update_service/widgets/update_dialog.dart"
  "lib/desktop/spotify/spotify_playlist_page.dart"
  "lib/desktop/ytmusic/mixins/playlists.dart"
  "lib/desktop/ytmusic/modals/user.dart"
  "lib/desktop/ytmusic/yt_service_provider.dart"
  "lib/mobile/diwali/diwali_welcome_dialog.dart"
  "lib/mobile/services/download_service.dart"
  "lib/mobile/services/local_cache_service.dart"
)
moved=0; kept=0
for rel in "${CANDIDATES[@]}"; do
  [ -f "$rel" ] || { echo "skip (already gone): $rel"; continue; }
  name=$(basename "$rel" .dart)
  hit=$(grep -rl --include=*.dart --include=*.yaml --include=*.kt --include=*.xml --include=*.gradle --include=*.kts "$name" lib test pubspec.yaml android/app/src 2>/dev/null | grep -v -x -F "$rel" | while read -r f; do
          skip=0; for c in "${CANDIDATES[@]}"; do [ "$f" = "$c" ] && skip=1; done; [ $skip = 0 ] && echo "$f" && break; done)
  if [ -n "$hit" ]; then echo "KEEP  $rel  (still mentioned in: $hit)"; kept=$((kept+1)); continue; fi
  if [ $APPLY = 1 ]; then mkdir -p "_unused_backup/$(dirname "$rel")"; mv "$rel" "_unused_backup/$rel"; echo "MOVED $rel"; else echo "would move  $rel"; fi
  moved=$((moved+1))
done
echo "$moved file(s) processed, $kept kept. $([ $APPLY = 1 ] || echo 'Dry run - rerun with --apply.')"
