import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../theme.dart';
import 'player_screen.dart';

/// Gen Playlists browser — mirrors PIGv4's PlayLists tab.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Playlist> _playlists = [];
  Map<int, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _loading = true);
    final db = DatabaseService();
    _playlists = await db.getAllPlaylists();
    _counts = await db.getPlaylistSongCounts();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with add button
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text(
                '${_playlists.length} Gen Playlists',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: PigTheme.hotPink),
                onPressed: _createPlaylist,
                tooltip: 'New Playlist',
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _playlists.isEmpty
                  ? const Center(
                      child: Text(
                        'No playlists yet.\nTap + to create one.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _playlists.length,
                      itemBuilder: (context, index) {
                        final pl = _playlists[index];
                        final count = _counts[pl.id] ?? 0;
                        return _PlaylistTile(
                          playlist: pl,
                          filterCount: count,
                          onTap: () => _openPlaylist(pl),
                          onDelete: () => _deletePlaylist(pl),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PigTheme.darkNavy,
        title: const Text('New Gen Playlist',
            style: TextStyle(color: PigTheme.hotPink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final db = DatabaseService();
      await db.insertPlaylist(Playlist(title: name));
      _loadPlaylists();
    }
  }

  Future<void> _deletePlaylist(Playlist pl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PigTheme.darkNavy,
        title: const Text('Delete Playlist',
            style: TextStyle(color: PigTheme.hotPink)),
        content: Text('Delete "${pl.title}"?',
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && pl.id != null) {
      final db = DatabaseService();
      await db.deletePlaylist(pl.id!);
      _loadPlaylists();
    }
  }

  void _openPlaylist(Playlist pl) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _PlaylistDetailScreen(playlist: pl)),
    ).then((_) => _loadPlaylists());
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final int filterCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PlaylistTile({
    required this.playlist,
    required this.filterCount,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a3e), width: 1)),
      ),
      child: ListTile(
        dense: true,
        leading:
            const Icon(Icons.queue_music, color: PigTheme.goldenrod, size: 24),
        title: Text(playlist.title,
            style: const TextStyle(color: PigTheme.hotPink, fontSize: 14)),
        subtitle: Text('$filterCount filter entries',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Playlist detail — shows resolved songs.
class _PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const _PlaylistDetailScreen({required this.playlist});

  @override
  State<_PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<_PlaylistDetailScreen> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    if (widget.playlist.id == null) return;
    final db = DatabaseService();
    _songs = await db.resolvePlaylistSongs(widget.playlist.id!);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTheme.darkNavy,
      appBar: AppBar(
        title: Text(widget.playlist.title),
        backgroundColor: PigTheme.navy,
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Play all',
              onPressed: () {
                final audio = context.read<AudioService>();
                audio.setPlaylist(_songs, startIndex: 0);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PlayerScreen()));
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? const Center(
                  child: Text(
                    'No songs in this playlist yet.\nAssign songs from the Songs tab.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${_songs.length} songs (resolved)',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _songs.length,
                        itemBuilder: (context, index) {
                          final song = _songs[index];
                          return ListTile(
                            dense: true,
                            title: Text(song.displayTitle,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            subtitle: Text(
                              '${song.displayArtist}${song.displayAlbum.isNotEmpty ? ' • ${song.displayAlbum}' : ''}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                            trailing: Text(song.durationFormatted,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            onTap: () {
                              final audio = context.read<AudioService>();
                              audio.setPlaylist(_songs, startIndex: index);
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const PlayerScreen()));
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
