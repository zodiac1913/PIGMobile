import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../theme.dart';

/// Songs browser with lazy loading — loads 50 at a time, fetches more on scroll.
class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  static const _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Song> _songs = [];
  List<String> _folders = [];
  String? _selectedFolder;
  bool _newOnly = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    final db = DatabaseService();
    _folders = await db.getDistinctFolders();
    await _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _songs.clear();
      _hasMore = true;
    });
    final db = DatabaseService();
    final search = _searchController.text.trim();
    final results = await db.getAllSongs(
      search: search.isEmpty ? null : search,
      folder: _selectedFolder,
      newOnly: _newOnly ? true : null,
      limit: _pageSize,
      offset: 0,
    );
    _totalCount = await db.getSongCount(
      search: search.isEmpty ? null : search,
      folder: _selectedFolder,
    );
    setState(() {
      _songs.addAll(results);
      _hasMore = results.length >= _pageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final db = DatabaseService();
    final search = _searchController.text.trim();
    final results = await db.getAllSongs(
      search: search.isEmpty ? null : search,
      folder: _selectedFolder,
      newOnly: _newOnly ? true : null,
      limit: _pageSize,
      offset: _songs.length,
    );
    setState(() {
      _songs.addAll(results);
      _hasMore = results.length >= _pageSize;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar + filters
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '🔍 Search songs...',
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _search();
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: (_) => _search(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedFolder,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        hintText: 'All Folders',
                      ),
                      dropdownColor: PigTheme.darkNavy,
                      style: const TextStyle(
                          color: PigTheme.hotPink, fontSize: 13),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All Folders')),
                        ..._folders.map((f) =>
                            DropdownMenuItem(value: f, child: Text(f))),
                      ],
                      onChanged: (val) {
                        _selectedFolder = val;
                        _search();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('New', style: TextStyle(fontSize: 12)),
                    selected: _newOnly,
                    selectedColor: PigTheme.hotPink,
                    onSelected: (val) {
                      _newOnly = val;
                      _search();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        // Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '$_totalCount songs${_songs.length < _totalCount ? ' (loaded ${_songs.length})' : ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Spacer(),
              if (_songs.isNotEmpty)
                TextButton.icon(
                  onPressed: _playAll,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Play All', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        // Song list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _songs.isEmpty
                  ? const Center(
                      child: Text('No songs found',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _songs.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _songs.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          );
                        }
                        return _SongTile(
                          song: _songs[index],
                          onTap: () => _playSong(index),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _playSong(int index) {
    final audio = context.read<AudioService>();
    audio.setPlaylist(_songs, startIndex: index);
  }

  void _playAll() {
    final audio = context.read<AudioService>();
    audio.setPlaylist(_songs, startIndex: 0);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _SongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final isActive = audio.currentSong?.id == song.id;

    return Container(
      decoration: BoxDecoration(
        color: isActive ? PigTheme.maroon : Colors.transparent,
        border: const Border(
            bottom: BorderSide(color: Color(0xFF2a2a3e), width: 1)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: Text(
          song.displayTitle,
          style: TextStyle(
            color: isActive ? PigTheme.hotPink : Colors.white,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${song.displayArtist}${song.displayAlbum.isNotEmpty ? ' • ${song.displayAlbum}' : ''}',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (song.isNew)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: PigTheme.lawnGreen.withAlpha(50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('NEW',
                    style:
                        TextStyle(color: PigTheme.lawnGreen, fontSize: 10)),
              ),
            const SizedBox(width: 8),
            Text(
              song.durationFormatted,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
