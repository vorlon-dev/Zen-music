// ZenMusic · vorlon-dev

// ZenMusic — shared building blocks for settings screens.
//
// Look: inset grouped lists like the host platform's own Settings app.
// One surface tone, hairline dividers, one icon colour (muted neutral),
// sentence-case section titles. No tinted badges, gradients or glows.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:zenmusic/desktop/utils/zen_icons.dart';

const double _kRadius = 24; // outer corners of a group
const double _kInner = 6; // corners between rows
const double _kIconSize = 22;
const double _kTile = 40;
const double _kIconGap = 16;

/// Section title + one rounded surface holding rows separated by hairlines.
class ZenSection extends StatelessWidget {
  const ZenSection(
      {super.key, this.title, required this.children, this.tint});

  final String? title;
  final Color? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: Material(
                color: cs.surfaceContainer,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(i == 0 ? _kRadius : _kInner),
                  bottom: Radius.circular(
                      i == children.length - 1 ? _kRadius : _kInner),
                ),
                child: tint == null
                    ? children[i]
                    : ZenTint(color: tint!, child: children[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single row: neutral icon, title, optional subtitle, optional trailing
/// widget, optional chevron.
class ZenRow extends StatelessWidget {
  const ZenRow({
    super.key,
    required this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.iconColor,
    this.titleColor,
    this.tint,
  });

  final IconData icon;

  final Widget? leading;

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? iconColor;
  final Color? titleColor;

  /// Tile colour for the icon (defaults to the theme's container tone).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else
                ZenTile(
                    icon: icon,
                    color: tint ?? ZenTint.of(context),
                    iconColor: iconColor),
              const SizedBox(width: _kIconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge?.copyWith(
                            color: titleColor, fontWeight: FontWeight.w500)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                // Dropdowns and buttons never get more than ~40 % of the
                // row, so the title keeps room and never wraps per letter.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (MediaQuery.sizeOf(context).width * 0.4)
                        .clamp(96.0, 200.0),
                  ),
                  child: trailing!,
                ),
              ],
              if (chevron) ...[
                const SizedBox(width: 8),
                Icon(ZenIcons.chevron,
                    size: 18,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Row with a platform-adaptive switch.
class ZenSwitchRow extends StatelessWidget {
  const ZenSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ZenRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }
}

/// Row with a label + current value on top and a full-width slider below.
class ZenSliderRow extends StatelessWidget {
  const ZenSliderRow({
    super.key,
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              ZenTile(icon: icon),
              const SizedBox(width: _kIconGap),
              Expanded(child: Text(title, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500))),
              Text(valueLabel,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: _kTile + _kIconGap - 8),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain search field used on the settings home.
class ZenSearchField extends StatefulWidget {
  const ZenSearchField({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<ZenSearchField> createState() => _ZenSearchFieldState();
}

class _ZenSearchFieldState extends State<ZenSearchField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _c,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {});
      },
      decoration: InputDecoration(
        hintText: 'Search settings',
        prefixIcon: Icon(ZenIcons.search, size: 20, color: cs.onSurfaceVariant),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
          tooltip: 'Clear',
          icon: Icon(ZenIcons.clear, size: 18, color: cs.onSurfaceVariant),
          onPressed: () {
            _c.clear();
            widget.onChanged('');
            setState(() {});
          },
        ),
        filled: true,
        fillColor: cs.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(32),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}


/// Rounded-square icon tile used by every row.
class ZenTile extends StatelessWidget {
  const ZenTile({super.key, required this.icon, this.color, this.iconColor});
  final IconData icon;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.secondaryContainer;
    final fg = iconColor ??
        (color == null
            ? cs.onSecondaryContainer
            : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black87));
    return Container(
      width: _kTile,
      height: _kTile,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: _kIconSize, color: fg),
    );
  }
}

/// Tile that shows a bundled brand logo (assets/brands/*.svg).
class ZenBrandTile extends StatelessWidget {
  const ZenBrandTile(this.asset, {super.key, this.size = _kTile});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.35),
    child: SvgPicture.asset(asset, width: size, height: size),
  );
}

/// Names of the bundled brand logos.
class ZenBrands {
  ZenBrands._();
  static const spotify = 'assets/brands/spotify.svg';
  static const ytmusic = 'assets/brands/ytmusic.svg';
  static const lastfm = 'assets/brands/lastfm.svg';
  static const github = 'assets/brands/github.svg';
}

/// Pill-shaped segmented control (theme mode, UI theme, ...).
class ZenSegmented<T> extends StatelessWidget {
  const ZenSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: o.$1 == value ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (o.$3 != null) ...[
                      Icon(o.$3,
                          size: 18,
                          color: o.$1 == value
                              ? cs.onPrimary
                              : cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        o.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: o.$1 == value
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Big rounded quick-action button (icon over label).
class ZenQuickAction extends StatelessWidget {
  const ZenQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 24, color: cs.onSecondaryContainer),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer)),
          ]),
        ),
      ),
    );
  }
}

/// Section card for custom content (previews, segmented controls).
class ZenCard extends StatelessWidget {
  const ZenCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(_kRadius),
    ),
    child: child,
  );
}

/// Gives every [ZenRow] below it the same tile colour (one per group).
class ZenTint extends InheritedWidget {
  const ZenTint({super.key, required this.color, required super.child});
  final Color color;

  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZenTint>()?.color;

  @override
  bool updateShouldNotify(ZenTint old) => old.color != color;
}