import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../models/playlist.dart';

/// SQLite database service — mirrors PIGv4's PigContext.
class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'pig_mobile.db');

    // If the app DB doesn't exist, try to restore from the music folder backup
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      await _restoreFromBackup(dbPath);
    }

    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return db;
  }

  /// Backup the database to the music folder (survives app uninstall).
  Future<void> backupToMusicFolder() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'pig_mobile.db');
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return;

    // Close the database to ensure clean copy
    if (_db != null) {
      await _db!.close();
      _db = null;
    }

    const backupDir = '/storage/emulated/0/Music/.pig';
    final pigDir = Directory(backupDir);
    if (!await pigDir.exists()) {
      await pigDir.create(recursive: true);
    }

    final backupPath = p.join(backupDir, 'pig_mobile.db');
    await dbFile.copy(backupPath);

    // Reopen the database
    _db = await _initDb();
  }

  /// Restore database from the music folder backup.
  Future<void> _restoreFromBackup(String targetPath) async {
    const backupPath = '/storage/emulated/0/Music/.pig/pig_mobile.db';
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      try {
        await backupFile.copy(targetPath);
      } catch (_) {
        // If restore fails, we'll just start fresh
      }
    }
  }

  /// Auto-backup after significant operations (called after scan, rescan tags, etc).
  Future<void> autoBackup() async {
    try {
      await backupToMusicFolder();
    } catch (_) {
      // Non-critical — don't crash if backup fails
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE songs ADD COLUMN albumArt BLOB');
      await db.execute(
        'ALTER TABLE songs ADD COLUMN albumArtChecked INTEGER DEFAULT 0',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filePath TEXT NOT NULL UNIQUE,
        title TEXT,
        artist TEXT,
        album TEXT,
        genre TEXT,
        year INTEGER,
        durationMs INTEGER,
        bpm INTEGER,
        sourceFolder TEXT,
        isNew INTEGER DEFAULT 1,
        albumArt BLOB,
        albumArtChecked INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        minimum INTEGER DEFAULT 0,
        created TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE song_filters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlistId INTEGER NOT NULL,
        songId INTEGER NOT NULL,
        hasTitle INTEGER DEFAULT 0,
        hasArtist INTEGER DEFAULT 0,
        FOREIGN KEY (playlistId) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (songId) REFERENCES songs(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_songs_artist ON songs(artist)');
    await db.execute('CREATE INDEX idx_songs_genre ON songs(genre)');
    await db.execute('CREATE INDEX idx_songs_folder ON songs(sourceFolder)');
    await db.execute(
      'CREATE INDEX idx_filters_playlist ON song_filters(playlistId)',
    );
    await db.execute('CREATE INDEX idx_filters_song ON song_filters(songId)');
  }

  // ── Songs ──

  Future<int> insertSong(Song song) async {
    final db = await database;
    return await db.insert(
      'songs',
      song.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateSong(Song song) async {
    final db = await database;
    await db.update(
      'songs',
      song.toMap(),
      where: 'id = ?',
      whereArgs: [song.id],
    );
  }

  /// Get album art bytes for a song. Returns null if not cached.
  Future<List<int>?> getAlbumArt(int songId) async {
    final db = await database;
    final rows = await db.query(
      'songs',
      columns: ['albumArt', 'albumArtChecked'],
      where: 'id = ?',
      whereArgs: [songId],
    );
    if (rows.isEmpty) return null;
    return rows.first['albumArt'] as List<int>?;
  }

  /// Cache album art bytes for a song.
  Future<void> setAlbumArt(int songId, List<int>? artBytes) async {
    final db = await database;
    await db.update(
      'songs',
      {'albumArt': artBytes, 'albumArtChecked': 1},
      where: 'id = ?',
      whereArgs: [songId],
    );
  }

  /// Check if album art has been looked up already.
  Future<bool> isAlbumArtChecked(int songId) async {
    final db = await database;
    final rows = await db.query(
      'songs',
      columns: ['albumArtChecked'],
      where: 'id = ?',
      whereArgs: [songId],
    );
    if (rows.isEmpty) return false;
    return (rows.first['albumArtChecked'] as int?) == 1;
  }

  /// Get playlists that contain a specific song.
  Future<List<String>> getPlaylistNamesForSong(int songId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT p.title FROM playlists p
      INNER JOIN song_filters sf ON sf.playlistId = p.id
      WHERE sf.songId = ?
      ORDER BY p.title
    ''',
      [songId],
    );
    return rows.map((r) => r['title'] as String).toList();
  }

  Future<void> deleteSong(int id) async {
    final db = await database;
    await db.delete('song_filters', where: 'songId = ?', whereArgs: [id]);
    await db.delete('songs', where: 'id = ?', whereArgs: [id]);
  }

  Future<Song?> getSongByPath(String filePath) async {
    final db = await database;
    final rows = await db.query(
      'songs',
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    if (rows.isEmpty) return null;
    return Song.fromMap(rows.first);
  }

  Future<List<Song>> getAllSongs({
    String? search,
    String? folder,
    String? genre,
    String? artist,
    bool? newOnly,
    String? startsWith,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (folder != null) {
      where.add('sourceFolder = ?');
      args.add(folder);
    }
    if (genre != null) {
      where.add('genre = ?');
      args.add(genre);
    }
    if (artist != null) {
      where.add('artist = ?');
      args.add(artist);
    }
    if (newOnly == true) {
      where.add('isNew = 1');
    }
    if (startsWith != null) {
      where.add('artist LIKE ?');
      args.add('$startsWith%');
    } else if (search != null && search.isNotEmpty) {
      where.add(
        '(title LIKE ? OR artist LIKE ? OR album LIKE ? OR filePath LIKE ?)',
      );
      final term = '%$search%';
      args.addAll([term, term, term, term]);
    }

    final rows = await db.query(
      'songs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'artist COLLATE NOCASE, title COLLATE NOCASE',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  Future<int> getSongCount({String? search, String? folder}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (folder != null) {
      where.add('sourceFolder = ?');
      args.add(folder);
    }
    if (search != null && search.isNotEmpty) {
      where.add('(title LIKE ? OR artist LIKE ? OR album LIKE ?)');
      final term = '%$search%';
      args.addAll([term, term, term]);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM songs${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      args.isEmpty ? null : args,
    );
    return result.first['cnt'] as int;
  }

  // ── Distinct values for filters ──

  Future<List<String>> getDistinctFolders() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT sourceFolder FROM songs WHERE sourceFolder IS NOT NULL ORDER BY sourceFolder',
    );
    return rows.map((r) => r['sourceFolder'] as String).toList();
  }

  Future<List<String>> getDistinctGenres() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT genre FROM songs WHERE genre IS NOT NULL ORDER BY genre',
    );
    return rows.map((r) => r['genre'] as String).toList();
  }

  Future<List<String>> getDistinctArtists() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT artist FROM songs WHERE artist IS NOT NULL ORDER BY artist COLLATE NOCASE',
    );
    return rows.map((r) => r['artist'] as String).toList();
  }

  // ── Artists with counts ──

  Future<List<Map<String, dynamic>>> getArtistsWithCounts({
    String? search,
  }) async {
    final db = await database;
    String sql =
        'SELECT artist, COUNT(*) as songCount FROM songs WHERE artist IS NOT NULL';
    final args = <dynamic>[];
    if (search != null && search.isNotEmpty) {
      sql += ' AND artist LIKE ?';
      args.add('%$search%');
    }
    sql += ' GROUP BY artist ORDER BY artist COLLATE NOCASE';
    return await db.rawQuery(sql, args);
  }

  // ── Playlists ──

  Future<int> insertPlaylist(Playlist playlist) async {
    final db = await database;
    return await db.insert('playlists', playlist.toMap()..remove('id'));
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    final db = await database;
    await db.update(
      'playlists',
      playlist.toMap(),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  Future<void> deletePlaylist(int id) async {
    final db = await database;
    await db.delete('song_filters', where: 'playlistId = ?', whereArgs: [id]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await database;
    final rows = await db.query('playlists', orderBy: 'title COLLATE NOCASE');
    return rows.map((r) => Playlist.fromMap(r)).toList();
  }

  // ── Song Filters (playlist assignments) ──

  Future<void> setSongFilter(SongFilter filter) async {
    final db = await database;
    // Remove existing filter for this song+playlist combo
    await db.delete(
      'song_filters',
      where: 'playlistId = ? AND songId = ?',
      whereArgs: [filter.playlistId, filter.songId],
    );
    if (filter.hasTitle || filter.hasArtist) {
      await db.insert('song_filters', filter.toMap()..remove('id'));
    }
  }

  Future<List<SongFilter>> getFiltersForSong(int songId) async {
    final db = await database;
    final rows = await db.query(
      'song_filters',
      where: 'songId = ?',
      whereArgs: [songId],
    );
    return rows.map((r) => SongFilter.fromMap(r)).toList();
  }

  Future<List<SongFilter>> getFiltersForPlaylist(int playlistId) async {
    final db = await database;
    final rows = await db.query(
      'song_filters',
      where: 'playlistId = ?',
      whereArgs: [playlistId],
    );
    return rows.map((r) => SongFilter.fromMap(r)).toList();
  }

  /// Resolve all songs for a playlist — same logic as PIGv4's PlaylistResolver.
  /// HasTitle = that specific song. HasArtist = ALL songs by that artist.
  Future<List<Song>> resolvePlaylistSongs(int playlistId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT s.* FROM songs s
      WHERE s.id IN (
        SELECT sf.songId FROM song_filters sf
        WHERE sf.playlistId = ? AND sf.hasTitle = 1
      )
      UNION
      SELECT DISTINCT s2.* FROM songs s2
      WHERE s2.artist IN (
        SELECT DISTINCT s3.artist FROM songs s3
        INNER JOIN song_filters sf2 ON s3.id = sf2.songId
        WHERE sf2.playlistId = ? AND sf2.hasArtist = 1
        AND s3.artist IS NOT NULL
      )
      ORDER BY artist COLLATE NOCASE, title COLLATE NOCASE
    ''',
      [playlistId, playlistId],
    );
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Get playlist song counts for display.
  Future<Map<int, int>> getPlaylistSongCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT playlistId, COUNT(*) as cnt FROM song_filters GROUP BY playlistId',
    );
    final map = <int, int>{};
    for (final r in rows) {
      map[r['playlistId'] as int] = r['cnt'] as int;
    }
    return map;
  }

  /// Browse songs with multiple filter types (OR logic like PIGv4 player).
  Future<List<Song>> browseSongs({
    List<int>? playlistIds,
    List<String>? folders,
    List<String>? genres,
    List<String>? artists,
    List<int>? pickedSongIds,
  }) async {
    final db = await database;
    final parts = <String>[];
    final args = <dynamic>[];

    if (playlistIds != null && playlistIds.isNotEmpty) {
      for (final plId in playlistIds) {
        // Resolve each playlist
        final resolved = await resolvePlaylistSongs(plId);
        if (resolved.isNotEmpty) {
          final ids = resolved.map((s) => s.id).toList();
          parts.add(
            'SELECT * FROM songs WHERE id IN (${ids.map((_) => '?').join(',')})',
          );
          args.addAll(ids);
        }
      }
    }
    if (folders != null && folders.isNotEmpty) {
      parts.add(
        'SELECT * FROM songs WHERE sourceFolder IN (${folders.map((_) => '?').join(',')})',
      );
      args.addAll(folders);
    }
    if (genres != null && genres.isNotEmpty) {
      parts.add(
        'SELECT * FROM songs WHERE genre IN (${genres.map((_) => '?').join(',')})',
      );
      args.addAll(genres);
    }
    if (artists != null && artists.isNotEmpty) {
      parts.add(
        'SELECT * FROM songs WHERE artist IN (${artists.map((_) => '?').join(',')})',
      );
      args.addAll(artists);
    }
    if (pickedSongIds != null && pickedSongIds.isNotEmpty) {
      parts.add(
        'SELECT * FROM songs WHERE id IN (${pickedSongIds.map((_) => '?').join(',')})',
      );
      args.addAll(pickedSongIds);
    }

    if (parts.isEmpty) return [];

    // Christmas blackout — same logic as PIGv4
    final christmasFilter = _isChristmasSeason()
        ? ''
        : " AND sourceFolder != 'Christmas'";

    final sql =
        'SELECT DISTINCT * FROM (${parts.join(' UNION ')}) AS combined WHERE 1=1$christmasFilter ORDER BY artist COLLATE NOCASE, title COLLATE NOCASE';
    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Christmas season: Thanksgiving through Jan 15.
  bool _isChristmasSeason() {
    final today = DateTime.now();
    if (today.month == 1 && today.day <= 15) return true;
    // Find Thanksgiving: 4th Thursday of November
    final nov1 = DateTime(today.year, 11, 1);
    var dayOfWeek = nov1.weekday; // 1=Mon, 7=Sun
    // Thursday = 4
    var daysUntilThursday = (4 - dayOfWeek + 7) % 7;
    final firstThursday = nov1.add(Duration(days: daysUntilThursday));
    final thanksgiving = firstThursday.add(const Duration(days: 21));
    if (today.isAfter(thanksgiving) || today.isAtSameMomentAs(thanksgiving)) {
      return true;
    }
    return false;
  }
}
