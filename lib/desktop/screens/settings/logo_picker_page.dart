// ZenMusic — Logo picker (SP-80, reworks the SP-79 in-app picker).
//
// The user picks their favourite Zen logo; applying it switches the app's
// LAUNCHER icon — the icon on the phone's home screen, OUTSIDE the app —
// exactly as asked. It no longer rebrands anything inside the app (the
// home header and about page show the default mark again).
//
// Android implements the switch with activity-aliases: each logo slot is
// an <activity-alias> in AndroidManifest.xml with its own mipmap icon;
// ZenLauncherIcon.kt enables one alias and disables the rest through
// PackageManager (no restart, no permission).
//
// Previews: the built-in slots ship in assets/logos/ (zen_logo_1..9.png;
// "default" is assets/icon/logo.png). Extra files dropped into
// assets/logos/ appear in the grid automatically — to make one of them the
// launcher icon, save it over a slot file (assets/logos/zen_logo_<n>.png
// AND android/app/src/main/res/mipmap-*/zen_logo_<n>*.*) and rebuild.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show AssetManifest, rootBundle;

import 'package:zenmusic/desktop/services/launcher_icon.dart';

class LogoPickerPage extends StatefulWidget {
  const LogoPickerPage({super.key});

  @override
  State<LogoPickerPage> createState() => _LogoPickerPageState();
}

class _LogoPickerPageState extends State<LogoPickerPage> {
  late List<String> _slots; // LauncherIcon.slots + any extra previews found
  late String _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _slots = List<String>.from(LauncherIcon.slots);
    _current = 'default';
    _load();
  }

  Future<void> _load() async {
    final found = await _enumPreviewAssets();
    // Trust the native side on Android once it answers.
    final live = Platform.isAndroid ? await LauncherIcon.loadCurrent() : _current;
    if (!mounted) return;
    setState(() {
      _current = live;
      for (final name in found) {
        if (!_slots.contains(name)) _slots.add(name);
      }
    });
  }

  /// Enumerates assets/logos/*.png that exist in the bundle (so logos the
  /// user drops in show up with no code changes).
  static Future<List<String>> _enumPreviewAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final names = <String>[];
      for (final key in manifest.listAssets()) {
        final m =
            RegExp(r'^assets/logos/([A-Za-z0-9_\-]+)\.png$').firstMatch(key);
        if (m != null) names.add(m.group(1)!);
      }
      names.sort();
      return names;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _apply(String slot) async {
    if (_busy || slot == _current) return;
    _busy = true;
    final applied = await LauncherIcon.apply(slot);
    _busy = false;
    if (!mounted) return;
    setState(() => _current = applied ? slot : _current);
    final messenger = ScaffoldMessenger.of(context);
    if (applied) {
      messenger.showSnackBar(SnackBar(
        content:
            Text('Home-screen icon changed to ${_label(slot)}.'),
      ));
    } else if (!Platform.isAndroid) {
      messenger.showSnackBar(const SnackBar(
        content:
            Text('The home-screen icon can only be changed on Android.'),
      ));
    } else if (LauncherIcon.slots.contains(slot)) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'This logo slot is missing from the installed app. Rebuild and '
            'reinstall once (flutter run / flutter build apk) — the icon '
            'set ships inside the Android manifest and mipmaps.'),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(
            '"$_label(slot)" is a preview-only logo. To use it on the home '
            'screen, save it over a zen_logo_<n> slot file and rebuild.'),
      ));
    }
  }

  static String _label(String slot) => switch (slot) {
        'default' => 'Default',
        _ => slot.startsWith('zen_logo_')
            ? 'Zen ${slot.replaceFirst('zen_logo_', '')}'
            : slot,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(
            'Pick your favourite logo — it becomes the app icon on your '
            'home screen (outside the app).',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.86,
            ),
            itemCount: _slots.length,
            itemBuilder: (context, i) {
              final slot = _slots[i];
              return _LogoCell(
                slot: slot,
                label: _label(slot),
                selected: slot == _current,
                onTap: () => _apply(slot),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Want to add your own? Drop square PNGs into assets/logos/ '
            '(they show up here). To put one on the home screen, save it '
            'over a zen_logo_<n> slot file and rebuild the app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LogoCell extends StatelessWidget {
  const _LogoCell({
    required this.slot,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String slot;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final asset =
        slot == 'default' ? 'assets/icon/logo.png' : 'assets/logos/$slot.png';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      width: selected ? 3 : 1,
                      color: selected ? cs.primary : cs.outlineVariant,
                    ),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child:
                            Icon(Icons.image_outlined, color: cs.outline),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.check_rounded,
                          size: 14, color: cs.onPrimary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
