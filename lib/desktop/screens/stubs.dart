// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class _StubScaffold extends StatelessWidget {
  final String label;
  const _StubScaffold(this.label);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: const Center(
        child: _UnderDevelopmentNotice(),
      ),
    );
  }
}

/// Public variant for router-level sub-routes (settings/player, etc.).
class SubPageStub extends StatelessWidget {
  final String label;
  const SubPageStub({super.key, required this.label});

  @override
  Widget build(BuildContext context) => _StubScaffold(label);
}

class _UnderDevelopmentNotice extends StatelessWidget {
  const _UnderDevelopmentNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'This screen is under development',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'ZenMusic is built by a solo developer. If you find the app '
                  'useful, consider starring the repository — it fuels the '
                  'developer\'s motivation. Thanks for the support.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color
                    ?.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse('https://github.com/vorlon-dev/Zen-music');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.star_border),
              label: const Text('Visit the repo'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartDetailsStub extends StatelessWidget {
  const ChartDetailsStub({super.key});
  @override
  Widget build(BuildContext context) => const _StubScaffold('Chart details');
}

class SavedStub extends StatelessWidget {
  const SavedStub({super.key});
  @override
  Widget build(BuildContext context) => const _StubScaffold('Saved');
}

class SettingsStub extends StatelessWidget {
  const SettingsStub({super.key});
  @override
  Widget build(BuildContext context) => const _StubScaffold('Settings');
}
