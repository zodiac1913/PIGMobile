import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../theme.dart';

/// Artist browser with lazy loading.
class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _artists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    setState(() => _loading = true);
    final db = DatabaseService();
    _artists = await db.getArtistsWithCounts(
      search: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
    );
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '🔍 Search artists...',
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _loadArtists();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onChanged: (_) => _loadArtists(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_artists.length} artists',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _artists.isEmpty
                  ? const Center(
                      child: Text('No artists found',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _artists.length,
                      itemBuilder: (context, index) {
                        final a = _artists[index];
                        return _ArtistTile(
                          name: a['artist'] as String,
                          songCount: a['songCount'] as int,
                          onTap: () => _openArtist(a['artist'] as String),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _openArtist(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _ArtistDetailScreen(artistName: name)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _ArtistTile extends StatelessWidget {
  final String name;
  final int songCount;
  final VoidCallback onTap;

  const _ArtistTile(
      {required this.name, required this.songCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a3e), width: 1)),
      ),
      child: ListTile(
        dense: true,
        title: Text(name,
            style: const TextStyle(color: PigTheme.hotPink, fontSize: 14)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: PigTheme.maroon.withAlpha(100),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('$songCount',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Artist detail — lazy loads songs.
class _ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  const _ArtistDetailScreen({required this.artistName});

  @override
  State<_ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<_ArtistDetailScreen> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final db = DatabaseService();
    _songs = await db.getAllSongs(artist: widget.artistName);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTheme.darkNavy,
      appBar: AppBar(
        title: Text(widget.artistName),
        backgroundColor: PigTheme.navy,
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Play all',
              onPressed: () {
                context.read<AudioService>().setPlaylist(_songs, startIndex: 0);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (context, index) {
                final song = _songs[index];
                return ListTile(
                  dense: true,
                  title: Text(song.displayTitle,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    '${song.displayAlbum}${song.genre != null ? ' • ${song.genre}' : ''}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: Text(song.durationFormatted,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
                  onTap: () {
                    context
                        .read<AudioService>()
                        .setPlaylist(_songs, startIndex: index);
                    Navigator.pop(context);
                  },
                );
              },
            ),
    );
  }
}
