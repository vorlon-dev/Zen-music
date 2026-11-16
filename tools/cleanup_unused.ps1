# ZenMusic - remove Dart files nothing uses any more.
#
# SAFE BY DESIGN:
#  * Default is a DRY RUN: it only prints what it would do.
#  * A file is moved ONLY if no other .dart file (outside this list), no
#    test, and no pubspec/Android file mentions its name. Anything that is
#    still linked from somewhere is KEPT and reported.
#  * Nothing is deleted: files are MOVED to _unused_backup\ (same folder
#    structure), so you can put any of them back.
#
# Usage (PowerShell, from the project root):
#   .\tools\cleanup_unused.ps1            # dry run
#   .\tools\cleanup_unused.ps1 -Apply     # really move them
#   flutter analyze                         # must still be clean

param([switch]$Apply)

$candidates = @(
  'lib/desktop/liquid/pipeline_warmup.dart',
  'lib/desktop/lossless/lossless_prefs.dart',
  'lib/desktop/screens/settings/widgets/color_icon.dart',
  'lib/desktop/screens/stubs.dart',
  'lib/desktop/screens/youtube/youtube_page.dart',
  'lib/desktop/screens/youtube/yt_comments_sheet.dart',
  'lib/desktop/screens/youtube/yt_home_page.dart',
  'lib/desktop/screens/youtube/yt_shorts_feed.dart',
  'lib/desktop/services/listen_together_service.dart',
  'lib/desktop/services/update_service/models/update_info.dart',
  'lib/desktop/services/update_service/update_service.dart',
  'lib/desktop/services/update_service/widgets/update_checking_dialog.dart',
  'lib/desktop/services/update_service/widgets/update_dialog.dart',
  'lib/desktop/spotify/spotify_playlist_page.dart',
  'lib/desktop/ytmusic/mixins/playlists.dart',
  'lib/desktop/ytmusic/modals/user.dart',
  'lib/desktop/ytmusic/yt_service_provider.dart',
  'lib/mobile/diwali/diwali_welcome_dialog.dart',
  'lib/mobile/services/download_service.dart',
  'lib/mobile/services/local_cache_service.dart'
)

$root = (Get-Location).Path
$moved = 0; $kept = 0

$searchFiles = Get-ChildItem -Recurse -File -Include *.dart,*.yaml,*.kt,*.xml,*.gradle,*.kts `
  -Path lib, test, pubspec.yaml, android\app\src -ErrorAction SilentlyContinue

foreach ($rel in $candidates) {
  $path = Join-Path $root $rel
  if (-not (Test-Path $path)) { Write-Host "skip (already gone): $rel"; continue }

  $name = [IO.Path]::GetFileNameWithoutExtension($rel)
  $self = (Resolve-Path $path).Path
  $others = $candidates | ForEach-Object { (Join-Path $root $_) }

  $hits = $searchFiles | Where-Object {
    $_.FullName -ne $self -and ($others -notcontains $_.FullName)
  } | Select-String -Pattern $name -SimpleMatch -List

  if ($hits) {
    $kept++
    Write-Host "KEEP  $rel  (still mentioned in: $($hits[0].Path))" -ForegroundColor Yellow
    continue
  }

  if ($Apply) {
    $dest = Join-Path $root (Join-Path '_unused_backup' $rel)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Move-Item -Force $path $dest
    Write-Host "MOVED $rel" -ForegroundColor Green
  } else {
    Write-Host "would move  $rel"
  }
  $moved++
}

Write-Host ""
Write-Host "$moved file(s) $(if ($Apply) {'moved to _unused_backup\'} else {'would be moved (dry run)'}), $kept kept."
if (-not $Apply) { Write-Host "Run again with -Apply to do it." }
