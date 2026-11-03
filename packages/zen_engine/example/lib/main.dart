import 'package:flutter/material.dart';
import 'package:zen_engine/zen_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZenEngine.instance.init();
  runApp(const ZenEngineExampleApp());
}

class ZenEngineExampleApp extends StatelessWidget {
  const ZenEngineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenEngine Demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  List<ZenSong> _searchResults = [];
  bool _searching = false;

  void _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _searching = true);
    final results = await ZenEngine.search.search(query);
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZenEngine Music Player')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Search songs (JioSaavn & YouTube)...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final song = _searchResults[index];
                return ListTile(
                  leading: song.thumbnailUrl != null
                      ? Image.network(song.thumbnailUrl!, width: 48, height: 48, fit: BoxFit.cover)
                      : const Icon(Icons.music_note),
                  title: Text(song.title, maxLines: 1),
                  subtitle: Text('${song.artist} • ${song.source.name.toUpperCase()}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => ZenEngine.player.playSong(song),
                  ),
                );
              },
            ),
          ),
          // Player bar
          StreamBuilder<ZenPlayerState>(
            stream: ZenEngine.player.stateStream,
            initialData: ZenEngine.player.state,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final currentSong = state?.currentSong;
              if (currentSong == null) return const SizedBox.shrink();

              return Container(
                color: Colors.grey.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            currentSong.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        state?.isPlaying == true ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: () => ZenEngine.player.togglePlayPause(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
