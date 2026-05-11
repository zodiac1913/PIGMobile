import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/pig_web_service.dart';
import '../services/settings_service.dart';
import '../services/browse_state.dart';
import '../models/playlist.dart';
import '../theme.dart';

/// Browse screen — two collapsible panels: Music Selection and Queue.
/// Toggle between Local music and PIG Web music.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with AutomaticKeepAliveClientMixin {
  // Source toggle: false = Local, true = PIG Web
  bool _useWeb = false;
  final PigWebService _webService = PigWebService();

  // Filter data (current view)
  List<Playlist> _playlists = [];
  List<String> _folders = [];
  List<String> _genres = [];
  List<String> _artists = [];

  // LOCAL selections (preserved when switching)
  final Set<int> _localSelectedPlaylists = {};
  final Set<String> _localSelectedFolders = {};
  final Set<String> _localSelectedGenres = {};
  final Set<String> _localSelectedArtists = {};
  final Set<int> _localPickedSongIds = {};
  List<Song> _localSongs = [];

  // WEB selections (preserved when switching)
  final Set<int> _webSelectedPlaylists = {};
  final Set<String> _webSelectedFolders = {};
  final Set<String> _webSelectedGenres = {};
  final Set<String> _webSelectedArtists = {};
  List<Song> _webSongs = [];

  // Active references (point to local or web sets)
  Set<int> get _selectedPlaylists =>
      _useWeb ? _webSelectedPlaylists : _localSelectedPlaylists;
  Set<String> get _selectedFolders =>
      _useWeb ? _webSelectedFolders : _localSelectedFolders;
  Set<String> get _selectedGenres =>
      _useWeb ? _webSelectedGenres : _localSelectedGenres;
  Set<String> get _selectedArtists =>
      _useWeb ? _webSelectedArtists : _localSelectedArtists;
  Set<int> get _pickedSongIds => _localPickedSongIds; // Only local has picks

  List<Song> get _songs => _useWeb ? _webSongs : _localSongs;
  set _songs(List<Song> val) {
    if (_useWeb) {
      _webSongs = val;
    } else {
      _localSongs = val;
    }
  }

  bool _loading = false;
  bool _filtersLoaded = false;

  // Panel state
  bool _selectionOpen = true;
  bool _queueOpen = false;

  // Filter search
  final _playlistSearch = TextEditingController();
  final _folderSearch = TextEditingController();
  final _genreSearch = TextEditingController();
  final _artistSearch = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initWebService();
    _loadFilters();
  }

  Future<void> _initWebService() async {
    final settings = SettingsService();
    await settings.load();
    if (settings.pigWebUrl != null && settings.pigWebUrl!.isNotEmpty) {
      _webService.configure(settings.pigWebUrl!);
      if (settings.pigWebToken != null && settings.pigWebUsername != null) {
        _webService.setToken(settings.pigWebToken!, settings.pigWebUsername!);
      }
    }
  }

  Future<void> _loadFilters() async {
    setState(() => _filtersLoaded = false);
    try {
      if (_useWeb && _webService.isAuthenticated) {
        _playlists = await _webService.getPlaylists();
        _folders = await _webService.getFolders();
        _genres = await _webService.getGenres();
        _artists = await _webService.getArtists();
      } else {
        final db = DatabaseService();
        _playlists = await db.getAllPlaylists();
        _folders = await db.getDistinctFolders();
        _genres = await db.getDistinctGenres();
        _artists = await db.getDistinctArtists();
      }
    } catch (e) {
      debugPrint('Failed to load filters: $e');
    }
    setState(() => _filtersLoaded = true);
  }

  Future<void> _browse() async {
    if (!_hasAnyFilter()) {
      setState(() => _songs = []);
      return;
    }
    setState(() => _loading = true);
    try {
      if (_useWeb && _webService.isAuthenticated) {
        _songs = await _webService.browseSongs(
          listIds: _selectedPlaylists.isNotEmpty
              ? _selectedPlaylists.toList()
              : null,
          folders: _selectedFolders.isNotEmpty
              ? _selectedFolders.toList()
              : null,
          genres: _selectedGenres.isNotEmpty ? _selectedGenres.toList() : null,
          artists: _selectedArtists.isNotEmpty
              ? _selectedArtists.toList()
              : null,
        );
      } else {
        final db = DatabaseService();
        _songs = await db.browseSongs(
          playlistIds: _selectedPlaylists.isNotEmpty
              ? _selectedPlaylists.toList()
              : null,
          folders: _selectedFolders.isNotEmpty
              ? _selectedFolders.toList()
              : null,
          genres: _selectedGenres.isNotEmpty ? _selectedGenres.toList() : null,
          artists: _selectedArtists.isNotEmpty
              ? _selectedArtists.toList()
              : null,
          pickedSongIds: _pickedSongIds.isNotEmpty
              ? _pickedSongIds.toList()
              : null,
        );
      }
    } catch (e) {
      debugPrint('Browse failed: $e');
    }
    setState(() => _loading = false);

    // Push queue to shared state so Player can access it
    if (mounted) {
      context.read<BrowseState>().setQueue(
        _songs,
        isWeb: _useWeb,
        webService: _useWeb ? _webService : null,
      );
    }
  }

  bool _hasAnyFilter() =>
      _selectedPlaylists.isNotEmpty ||
      _selectedFolders.isNotEmpty ||
      _selectedGenres.isNotEmpty ||
      _selectedArtists.isNotEmpty ||
      _pickedSongIds.isNotEmpty;

  void _clearAll() {
    setState(() {
      _selectedPlaylists.clear();
      _selectedFolders.clear();
      _selectedGenres.clear();
      _selectedArtists.clear();
      if (!_useWeb) _pickedSongIds.clear();
      _songs = [];
    });
    context.read<BrowseState>().clear();
  }

  /// Get the current browse queue (used by Player to know what's selected).
  List<Song> get currentQueue => _songs;
  bool get isWebMode => _useWeb;
  PigWebService get webService => _webService;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_filtersLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Header: Pig logo + Web/Local toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: PigTheme.navy,
          child: Column(
            children: [
              // Pig icon + title row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/pigIconsnout.png',
                    width: 28,
                    height: 28,
                    errorBuilder: (_, e, s) => const Icon(
                      Icons.music_note,
                      size: 28,
                      color: PigTheme.hotPink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PIG',
                    style: TextStyle(
                      color: PigTheme.hotPink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Web / Local toggle buttons — full width
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_useWeb) {
                          setState(() => _useWeb = false);
                          _loadFilters();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_useWeb ? PigTheme.maroon : PigTheme.darkNavy,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8),
                          ),
                          border: Border.all(
                            color: !_useWeb
                                ? PigTheme.hotPink
                                : Colors.grey.shade700,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '📱 Local',
                            style: TextStyle(
                              color: !_useWeb ? PigTheme.hotPink : Colors.grey,
                              fontSize: 14,
                              fontWeight: !_useWeb
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!_useWeb) {
                          if (!_webService.isAuthenticated) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Login to PIG Web in Settings first',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            _useWeb = true;
                          });
                          _loadFilters();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _useWeb ? PigTheme.maroon : PigTheme.darkNavy,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(8),
                          ),
                          border: Border.all(
                            color: _useWeb
                                ? PigTheme.hotPink
                                : Colors.grey.shade700,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '🌐 Web',
                            style: TextStyle(
                              color: _useWeb ? PigTheme.hotPink : Colors.grey,
                              fontSize: 14,
                              fontWeight: _useWeb
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Music Selection panel header
        _panelHeader(
          title: 'Music Selection',
          icon: Icons.tune,
          isOpen: _selectionOpen,
          badge: _hasAnyFilter()
              ? '${_selectedPlaylists.length + _selectedFolders.length + _selectedGenres.length + _selectedArtists.length + (_pickedSongIds.isNotEmpty ? 1 : 0)}'
              : null,
          onTap: () => setState(() => _selectionOpen = !_selectionOpen),
          trailing: _hasAnyFilter()
              ? TextButton(
                  onPressed: _clearAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : null,
        ),
        // Music Selection content
        if (_selectionOpen)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _buildFilterSection(
                    icon: Icons.queue_music,
                    title: 'Gen Playlists',
                    count: _selectedPlaylists.length,
                    total: _playlists.length,
                    searchController: _playlistSearch,
                    items: _playlists,
                    isPlaylist: true,
                  ),
                  _buildFilterSection(
                    icon: Icons.folder,
                    title: 'Folders',
                    count: _selectedFolders.length,
                    total: _folders.length,
                    searchController: _folderSearch,
                    stringItems: _folders,
                    selected: _selectedFolders,
                  ),
                  _buildFilterSection(
                    icon: Icons.music_note,
                    title: 'Genres',
                    count: _selectedGenres.length,
                    total: _genres.length,
                    searchController: _genreSearch,
                    stringItems: _genres,
                    selected: _selectedGenres,
                  ),
                  _buildFilterSection(
                    icon: Icons.person,
                    title: 'Artists',
                    count: _selectedArtists.length,
                    total: _artists.length,
                    searchController: _artistSearch,
                    isArtist: true,
                  ),
                ],
              ),
            ),
          ),

        // Queue panel header
        _panelHeader(
          title: 'Queue',
          icon: Icons.playlist_play,
          isOpen: _queueOpen,
          badge: _songs.isNotEmpty ? '${_songs.length}' : null,
          onTap: () => setState(() => _queueOpen = !_queueOpen),
          trailing: null,
        ),
        // Queue content
        if (_queueOpen)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _songs.isEmpty
                ? const Center(
                    child: Text(
                      'No songs queued',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: _songs.length,
                    itemBuilder: (context, index) {
                      final song = _songs[index];
                      final audio = context.watch<AudioService>();
                      final isActive = audio.currentSong?.id == song.id;
                      return Container(
                        color: isActive ? PigTheme.maroon : Colors.transparent,
                        child: ListTile(
                          dense: true,
                          title: Text(
                            song.displayTitle,
                            style: TextStyle(
                              color: isActive ? PigTheme.hotPink : Colors.white,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song.displayArtist,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: null,
                        ),
                      );
                    },
                  ),
          ),

        // If both panels closed, show a hint
        if (!_selectionOpen && !_queueOpen)
          const Expanded(
            child: Center(
              child: Text(
                'Tap a panel header to expand',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _panelHeader({
    required String title,
    required IconData icon,
    required bool isOpen,
    String? badge,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: PigTheme.navy,
          border: const Border(
            bottom: BorderSide(color: PigTheme.maroon, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: PigTheme.goldenrod, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: PigTheme.hotPink,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ],
            const Spacer(),
            ?trailing,
            const SizedBox(width: 4),
            Icon(
              isOpen ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection({
    required IconData icon,
    required String title,
    required int count,
    required int total,
    required TextEditingController searchController,
    List<Playlist>? items,
    List<String>? stringItems,
    Set<String>? selected,
    bool isPlaylist = false,
    bool isArtist = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Icon(icon, color: PigTheme.goldenrod, size: 18),
        title: Row(
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: count > 0 ? PigTheme.hotPink : Colors.grey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 0 ? '$count' : '$total',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: '🔍 Filter...',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 180,
            child: isArtist
                ? _buildLazyArtistList()
                : isPlaylist
                ? _buildPlaylistList()
                : _buildStringList(stringItems!, selected!, searchController),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistList() {
    final filter = _playlistSearch.text.toLowerCase();
    final filtered = _playlists
        .where((p) => filter.isEmpty || p.title.toLowerCase().contains(filter))
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: filtered.length,
      itemExtent: 34,
      itemBuilder: (context, index) {
        final pl = filtered[index];
        return Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _selectedPlaylists.contains(pl.id),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedPlaylists.add(pl.id!);
                    } else {
                      _selectedPlaylists.remove(pl.id);
                    }
                  });
                  _browse();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pl.title,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStringList(
    List<String> items,
    Set<String> selected,
    TextEditingController search,
  ) {
    final filter = search.text.toLowerCase();
    final filtered = items
        .where((i) => filter.isEmpty || i.toLowerCase().contains(filter))
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: filtered.length,
      itemExtent: 34,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: selected.contains(item),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      selected.add(item);
                    } else {
                      selected.remove(item);
                    }
                  });
                  _browse();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLazyArtistList() {
    final filter = _artistSearch.text.toLowerCase();
    final filtered = _artists
        .where((a) => filter.isEmpty || a.toLowerCase().contains(filter))
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: filtered.length,
      itemExtent: 34,
      itemBuilder: (context, index) {
        final artist = filtered[index];
        return Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _selectedArtists.contains(artist),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedArtists.add(artist);
                    } else {
                      _selectedArtists.remove(artist);
                    }
                  });
                  _browse();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                artist,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => _openArtistSongs(artist),
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.music_note_outlined,
                  color: PigTheme.goldenrod,
                  size: 18,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openArtistSongs(String artist) async {
    final db = DatabaseService();
    final songs = await db.getAllSongs(artist: artist);
    if (songs.isEmpty || !mounted) return;

    final checked = <int>{};
    for (final s in songs) {
      if (s.id != null && _pickedSongIds.contains(s.id)) checked.add(s.id!);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PigTheme.darkNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: PigTheme.maroon, width: 2),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: PigTheme.maroon,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              artist,
                              style: const TextStyle(
                                color: PigTheme.hotPink,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${checked.length} selected',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => setSheetState(
                              () => checked.addAll(
                                songs
                                    .where((s) => s.id != null)
                                    .map((s) => s.id!),
                              ),
                            ),
                            child: const Text(
                              'Select All',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setSheetState(() => checked.clear()),
                            child: const Text(
                              'None',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: songs.length,
                        itemBuilder: (ctx, i) {
                          final song = songs[i];
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            value: song.id != null && checked.contains(song.id),
                            onChanged: (val) {
                              if (song.id == null) return;
                              setSheetState(() {
                                if (val == true) {
                                  checked.add(song.id!);
                                } else {
                                  checked.remove(song.id);
                                }
                              });
                            },
                            title: Text(
                              song.displayTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: song.displayAlbum.isNotEmpty
                                ? Text(
                                    song.displayAlbum,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            for (final s in songs) {
                              if (s.id != null) _pickedSongIds.remove(s.id);
                            }
                            _pickedSongIds.addAll(checked);
                            Navigator.pop(ctx);
                            _browse();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: PigTheme.maroon,
                            foregroundColor: PigTheme.hotPink,
                          ),
                          child: const Text('Apply'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _playlistSearch.dispose();
    _folderSearch.dispose();
    _genreSearch.dispose();
    _artistSearch.dispose();
    super.dispose();
  }
}
