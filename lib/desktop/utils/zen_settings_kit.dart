// ZenMusic — shared building blocks for settings screens.
//
// Look: inset grouped lists like the host platform's own Settings app.
// One surface tone, hairline dividers, one icon colour (muted neutral),
// sentence-case section titles. No tinted badges, gradients or glows.

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/utils/zen_icons.dart';

const double _kRadius = 14;
const double _kIconSize = 22;
const double _kIconGap = 16;

/// Section title + one rounded surface holding rows separated by hairlines.
class ZenSection extends StatelessWidget {
  const ZenSection({super.key, this.title, required this.children});

  final String? title;
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
          Material(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(_kRadius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 16 + _kIconSize + _kIconGap,
                      color: cs.outlineVariant.withValues(alpha: 0.7),
                    ),
                  children[i],
                ],
              ],
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
    // SP-62: optional brand-logo slot — overrides [icon] when set.
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;

  /// SP-62: fully custom leading widget (Spotify / YouTube Music logos).
  final Widget? leading;

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // SP-62: brand logos (or any custom widget) take the icon slot.
              if (leading != null)
                leading!
              else
                Icon(icon,
                    size: _kIconSize,
                    color: iconColor ?? cs.onSurfaceVariant),
              const SizedBox(width: _kIconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: tt.bodyLarge?.copyWith(color: titleColor)),
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
                trailing!,
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
              Icon(icon, size: _kIconSize, color: cs.onSurfaceVariant),
              const SizedBox(width: _kIconGap),
              Expanded(child: Text(title, style: tt.bodyLarge)),
              Text(valueLabel,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: _kIconSize + _kIconGap - 8),
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
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kRadius),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}