import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'pig_web_service.dart';

/// Shared state between Browse and Player.
/// Browse writes the queue here. Player reads it.
/// The queue AND browse selections persist in SQLite until the user explicitly
/// clears them. Designed for future "saved queues" (named selection sets).
class BrowseState extends ChangeNotifier {
  List<Song> _queue = [];
  bool _isWeb = false;
  PigWebService? _webService;
  bool _loaded = false;

  // Persisted browse selections (the checkboxes)
  Set<int> _selectedPlaylistIds = {};
  Set<String> _selectedFolders = {};
  Set<String> _selectedGenres = {};
  Set<String> _selectedArtists = {};
  Set<int> _pickedSongIds = {};

  List<Song> get queue => _queue;
  bool get hasQueue => _queue.isNotEmpty;
  bool get isWeb => _isWeb;
  bool get loaded => _loaded;
  PigWebService? get webService => _webService;

  // Selection getters
  Set<int> get selectedPlaylistIds => _selectedPlaylistIds;
  Set<String> get selectedFolders => _selectedFolders;
  Set<String> get selectedGenres => _selectedGenres;
  Set<String> get selectedArtists => _selectedArtists;
  Set<int> get pickedSongIds => _pickedSongIds;
  bool get hasSelections =>
      _selectedPlaylistIds.isNotEmpty ||
      _selectedFolders.isNotEmpty ||
      _selectedGenres.isNotEmpty ||
      _selectedArtists.isNotEmpty ||
      _pickedSongIds.isNotEmpty;

  /// Load the persisted queue and selections from the database on app start.
  Future<void> loadPersistedQueue() async {
    if (_loaded) return;
    final db = DatabaseService();

    // Load queue songs
    final songs = await db.loadQueue();
    if (songs.isNotEmpty) {
      _queue = songs;
      _isWeb = false; // Persisted queue is always local songs
    }

    // Load browse selections (checkboxes)
    final selections = await db.loadBrowseSelections();
    if (selections != null) {
      _selectedPlaylistIds = _toIntSet(selections['playlistIds']);
      _selectedFolders = _toStringSet(selections['folders']);
      _selectedGenres = _toStringSet(selections['genres']);
      _selectedArtists = _toStringSet(selections['artists']);
      _pickedSongIds = _toIntSet(selections['pickedSongIds']);
    }

    _loaded = true;
    notifyListeners();
  }

  void setQueue(
    List<Song> songs, {
    bool isWeb = false,
    PigWebService? webService,
  }) {
    _queue = songs;
    _isWeb = isWeb;
    _webService = webService;
    notifyListeners();

    // Persist local queues to survive app restarts
    if (!isWeb) {
      _persistQueue(songs);
    }
  }

  /// Update the persisted browse selections (called when checkboxes change).
  void setSelections({
    required Set<int> playlistIds,
    required Set<String> folders,
    required Set<String> genres,
    required Set<String> artists,
    required Set<int> pickedSongIds,
  }) {
    _selectedPlaylistIds = Set.from(playlistIds);
    _selectedFolders = Set.from(folders);
    _selectedGenres = Set.from(genres);
    _selectedArtists = Set.from(artists);
    _pickedSongIds = Set.from(pickedSongIds);
    _persistSelections();
  }

  /// Clear the queue and selections — explicit user action only.
  void clear() {
    _queue = [];
    _isWeb = false;
    _webService = null;
    _selectedPlaylistIds = {};
    _selectedFolders = {};
    _selectedGenres = {};
    _selectedArtists = {};
    _pickedSongIds = {};
    notifyListeners();

    // Clear persisted data from database
    _clearPersistedQueue();
    _clearPersistedSelections();
  }

  Future<void> _persistQueue(List<Song> songs) async {
    try {
      final db = DatabaseService();
      await db.saveQueue(songs);
    } catch (e) {
      debugPrint('PIG: Failed to persist queue: $e');
    }
  }

  Future<void> _persistSelections() async {
    try {
      final db = DatabaseService();
      await db.saveBrowseSelections(
        playlistIds: _selectedPlaylistIds,
        folders: _selectedFolders,
        genres: _selectedGenres,
        artists: _selectedArtists,
        pickedSongIds: _pickedSongIds,
      );
    } catch (e) {
      debugPrint('PIG: Failed to persist browse selections: $e');
    }
  }

  Future<void> _clearPersistedQueue() async {
    try {
      final db = DatabaseService();
      await db.clearQueue();
    } catch (e) {
      debugPrint('PIG: Failed to clear persisted queue: $e');
    }
  }

  Future<void> _clearPersistedSelections() async {
    try {
      final db = DatabaseService();
      await db.clearBrowseSelections();
    } catch (e) {
      debugPrint('PIG: Failed to clear persisted selections: $e');
    }
  }

  // ── Helpers ──

  Set<int> _toIntSet(dynamic list) {
    if (list is List) {
      return list.map((e) => (e as num).toInt()).toSet();
    }
    return {};
  }

  Set<String> _toStringSet(dynamic list) {
    if (list is List) {
      return list.map((e) => e.toString()).toSet();
    }
    return {};
  }
}
