import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'pig_web_service.dart';

/// Shared state between Browse and Player.
/// Browse writes the queue here. Player reads it.
/// The queue persists in SQLite until the user explicitly clears it.
class BrowseState extends ChangeNotifier {
  List<Song> _queue = [];
  bool _isWeb = false;
  PigWebService? _webService;
  bool _loaded = false;

  List<Song> get queue => _queue;
  bool get hasQueue => _queue.isNotEmpty;
  bool get isWeb => _isWeb;
  bool get loaded => _loaded;
  PigWebService? get webService => _webService;

  /// Load the persisted queue from the database on app start.
  Future<void> loadPersistedQueue() async {
    if (_loaded) return;
    final db = DatabaseService();
    final songs = await db.loadQueue();
    if (songs.isNotEmpty) {
      _queue = songs;
      _isWeb = false; // Persisted queue is always local songs
      notifyListeners();
    }
    _loaded = true;
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

  /// Clear the queue — explicit user action only.
  void clear() {
    _queue = [];
    _isWeb = false;
    _webService = null;
    notifyListeners();

    // Clear persisted queue from database
    _clearPersistedQueue();
  }

  Future<void> _persistQueue(List<Song> songs) async {
    try {
      final db = DatabaseService();
      await db.saveQueue(songs);
    } catch (e) {
      debugPrint('PIG: Failed to persist queue: $e');
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
}
