import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';
import 'extension_feed_view.dart' show parseHexColor;

/// Modal source picker: vertical single-select toggle list with a
/// connected Manage / Add button group underneath.
/// [onSelect] receives the tapped source id — null means the built-in
/// sources. Dismissing the sheet without tapping calls nothing.
Future<void> showSourcePickerSheet({
  required BuildContext context,
  required List<Map<String, dynamic>> extensions,
  required String? activeId,
  required Future<void> Function(String? id) onSelect,
  required VoidCallback onOpenManager,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: SpotifyColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: _SourcePickerBody(
        extensions: extensions,
        activeId: activeId,
        onSelect: onSelect,
        onOpenManager: onOpenManager,
      ),
    ),
  );
}

class _SourcePickerBody extends StatelessWidget {
  _SourcePickerBody({
    required this.extensions,
    required this.activeId,
    required this.onSelect,
    required this.onOpenManager,
  });

  final List<Map<String, dynamic>> extensions;
  final String? activeId;
  final Future<void> Function(String? id) onSelect;
  final VoidCallback onOpenManager;

  void _pick(BuildContext context, String? id) {
    Navigator.of(context).pop();
    onSelect(id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SourceToggleRow(
                  label: 'Default',
                  iconData: Icons.music_note_rounded,
                  active: activeId == null,
                  onTap: () => _pick(context, null),
                ),
                for (final ext in extensions)
                  _SourceToggleRow(
                    label: ext['name']?.toString() ?? 'Extension',
                    iconData: Icons.extension_rounded,
                    icon: _extractIcon(ext['icon']),
                    active: ext['id']?.toString() == activeId,
                    onTap: () => _pick(context, ext['id']?.toString()),
                  ),
                if (extensions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8, left: 4),
                    child: Text(
                      'Install extensions to add more sources',
                      style: TextStyle(
                        color: SpotifyColors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _bottomActions(context),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'Music Extensions',
              style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Positioned(
              left: 0,
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: SpotifyColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: _SheetActionButton(
              label: 'Manage',
              icon: Icons.extension_rounded,
              filled: false,
              onTap: () {
                Navigator.of(context).pop();
                onOpenManager();
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SheetActionButton(
              label: 'Add',
              icon: Icons.add_circle_outline_rounded,
              filled: true,
              onTap: () {
                Navigator.of(context).pop();
                onOpenManager();
              },
            ),
          ),
        ],
      ),
    );
  }
}

({String url, Map<String, String> headers, String? hex})? _extractIcon(
    dynamic icon) {
  if (icon is! Map) return null;
  final url = icon['url']?.toString() ?? '';
  if (url.isEmpty && icon['hex'] == null) return null;
  final headers = <String, String>{};
  final rawHeaders = icon['headers'];
  if (rawHeaders is Map) {
    rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
  }
  return (
  url: url,
  headers: headers,
  hex: icon['hex']?.toString(),
  );
}

class _SourceToggleRow extends StatelessWidget {
  _SourceToggleRow({
    required this.label,
    required this.iconData,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData iconData;
  final bool active;
  final VoidCallback onTap;
  final ({String url, Map<String, String> headers, String? hex})? icon;

  static const double _iconSize = 32;

  Widget _leading() {
    final data = icon;
    if (data != null) {
      final color = parseHexColor(data.hex);
      if (color != null) {
        return Container(
          width: _iconSize,
          height: _iconSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        );
      }
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: data.url,
          httpHeaders: data.headers.isEmpty ? null : data.headers,
          width: _iconSize,
          height: _iconSize,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: SpotifyColors.surfaceLight),
          errorWidget: (_, __, ___) => Container(
            color: SpotifyColors.surfaceLight,
            child: Icon(
              iconData,
              size: 18,
              color: SpotifyColors.textSecondary,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: Center(
        child: Icon(
          iconData,
          size: 20,
          color: active
              ? SpotifyColors.background
              : SpotifyColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? SpotifyColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color: active
                  ? SpotifyColors.textPrimary
                  : SpotifyColors.textTertiary.withOpacity(0.35),
            ),
          ),
          child: Row(
            children: [
              _leading(),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? SpotifyColors.background
                        : SpotifyColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  _SheetActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? SpotifyColors.green : SpotifyColors.surfaceLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: filled ? Colors.black : SpotifyColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.black : SpotifyColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}