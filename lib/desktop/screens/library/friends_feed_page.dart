// ZenMusic · what your Last.fm friends are playing.
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zenmusic/desktop/services/lastfm_service.dart';
import 'package:zenmusic/desktop/services/smart_mix_service.dart';

class FriendsFeedPage extends StatefulWidget {
  const FriendsFeedPage({super.key});
  @override
  State<FriendsFeedPage> createState() => _FriendsFeedPageState();
}

class _FriendsFeedPageState extends State<FriendsFeedPage> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final user = LastfmService.instance.user.value;
    _future = user == null ? null : SmartMixService.instance.friendsFeed(user);
  }

  @override
  Widget build(BuildContext context) {
    final user = LastfmService.instance.user.value;
    return Scaffold(
      appBar: AppBar(title: Text('Friends feed'.tr)),
      body: user == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Connect your Last.fm account in Settings to see what your friends are playing.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                setState(_load);
                await _future;
              },
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No friends found, or Last.fm could not be reached. Pull down to retry.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ]);
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final f = list[i];
                      final has = (f['track'] as String).isNotEmpty;
                      final img = f['image'] as String;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: img.isEmpty ? null : NetworkImage(img),
                          child: img.isEmpty ? Text((f['name'] as String).isEmpty ? '?' : (f['name'] as String)[0].toUpperCase()) : null,
                        ),
                        title: Text(f['name'] as String),
                        subtitle: Text(
                          has ? '${f['artist']} · ${f['track']}' : 'Nothing played recently',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: f['nowPlaying'] == true
                            ? Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: (f['url'] as String).isEmpty
                            ? null
                            : () => launchUrl(Uri.parse(f['url'] as String),
                                mode: LaunchMode.externalApplication),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
