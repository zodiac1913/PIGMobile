import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import 'database_service.dart';

/// Scans the device music folder for MP3 files and imports them into the database.
/// Reads ID3 tags. Imports .m3u playlists as Gen Playlists.
class ScannerService {
  final DatabaseService _db;

  ScannerService(this._db);

  static const _audioExtensions = {
    '.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac', '.wma', '.opus'
  };

  /// Scan a directory tree for audio files and .m3u playlists.
  Future<ScanResult> scanDirectory(
    String directoryPath, {
    void Function(String status, int current, int total)? onProgress,
  }) async {
    final rootDir = Directory(directoryPath);
    if (!await rootDir.exists()) {
      return ScanResult(error: 'Directory not found: $directoryPath');
    }

    final rootName = rootDir.path.split('/').last;

    // Phase 1: Collect files
    onProgress?.call('Discovering files...', 0, 0);
    final audioFiles = <File>[];
    final m3uFiles = <File>[];
    await _collectFiles(rootDir, audioFiles, m3uFiles);

    // Phase 2: Import audio files with ID3 tags
    int songsImported = 0;
    int songsSkipped = 0;
    for (int i = 0; i < audioFiles.length; i++) {
      final file = audioFiles[i];
      final fileName = file.path.split('/').last;
      onProgress?.call(fileName, i + 1, audioFiles.length);

      final existing = await _db.getSongByPath(file.path);
      if (existing != null) {
        songsSkipped++;
        continue;
      }

      final sourceFolder =
          _getSourceFolder(file.path, directoryPath, rootName);

      String? title;
      String? artist;
      String? album;
      String? genre;
      int? year;
      int? durationMs;

      try {
        final metadata = readMetadata(file, getImage: false);
        title = metadata.title;
        artist = metadata.artist;
        album = metadata.album;
        genre = metadata.genres.isNotEmpty ? metadata.genres.first : null;
        year = metadata.year?.year;
        durationMs = metadata.duration?.inMilliseconds;
      } catch (_) {}

      if ((title == null || title.isEmpty) ||
          (artist == null || artist.isEmpty)) {
        final parsed = _parseFileName(fileName);
        title = (title != null && title.isNotEmpty) ? title : parsed.title;
        artist =
            (artist != null && artist.isNotEmpty) ? artist : parsed.artist;
      }

      final song = Song(
        filePath: file.path,
        title: title,
        artist: artist,
        album: (album != null && album.isNotEmpty) ? album : null,
        genre: (genre != null && genre.isNotEmpty) ? genre : null,
        year: year,
        durationMs: durationMs,
        sourceFolder: sourceFolder,
        isNew: true,
      );

      await _db.insertSong(song);
      songsImported++;
    }

    // Phase 3: Import .m3u playlists — build lookup map ONCE
    int playlistsImported = 0;
    if (m3uFiles.isNotEmpty) {
      onProgress?.call('Loading song index for playlists...', 0, 0);
      // Build lookup maps for fast matching
      final allSongs = await _db.getAllSongs();
      final pathMap = <String, Song>{};
      final fileNameMap = <String, Song>{};
      for (final s in allSongs) {
        pathMap[s.filePath] = s;
        final fn = s.filePath.split('/').last.toLowerCase();
        fileNameMap[fn] = s;
      }

      for (int i = 0; i < m3uFiles.length; i++) {
        final m3uFile = m3uFiles[i];
        onProgress?.call(
            'Playlist: ${m3uFile.path.split('/').last}',
            i + 1,
            m3uFiles.length);
        try {
          final imported = await _importM3u(m3uFile, directoryPath, pathMap, fileNameMap);
          if (imported) playlistsImported++;
        } catch (_) {
          // Skip broken playlist files
        }
      }
    }

    return ScanResult(
      songsImported: songsImported,
      songsSkipped: songsSkipped,
      totalAudioFiles: audioFiles.length,
      playlistsImported: playlistsImported,
      totalPlaylists: m3uFiles.length,
    );
  }

  Future<void> _collectFiles(
      Directory dir, List<File> audioFiles, List<File> m3uFiles) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final lower = entity.path.toLowerCase();
          final dotIdx = lower.lastIndexOf('.');
          if (dotIdx < 0) continue;
          final ext = lower.substring(dotIdx);
          if (_audioExtensions.contains(ext)) {
            audioFiles.add(entity);
          } else if (ext == '.m3u' || ext == '.m3u8') {
            m3uFiles.add(entity);
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last;
          if (dirName.startsWith('.')) continue;
          await _collectFiles(entity, audioFiles, m3uFiles);
        }
      }
    } on PathAccessException {
      // Skip restricted dirs
    } on FileSystemException {
      // Skip errors
    }
  }

  String? _getSourceFolder(String filePath, String rootPath, String rootName) {
    final root = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    if (!filePath.startsWith(root)) return null;
    final relative = filePath.substring(root.length);
    final parts = relative.split('/');
    if (parts.length <= 1) return null;
    return parts[0];
  }

  _ParsedFileName _parseFileName(String fileName) {
    var name = fileName;
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx > 0) name = name.substring(0, dotIdx);

    final dashIdx = name.indexOf(' - ');
    if (dashIdx > 0) {
      final artist = name.substring(0, dashIdx).trim();
      var title = name.substring(dashIdx + 3).trim();
      title = title.replaceFirst(RegExp(r'^\d{1,3}[\.\s]+'), '');
      return _ParsedFileName(title: title, artist: artist);
    }

    name = name.replaceAll('_', ' ');
    name = name.replaceFirst(RegExp(r'^\d{1,3}[\.\s]+'), '');
    return _ParsedFileName(title: name.trim(), artist: null);
  }

  /// Import a .m3u playlist using pre-built lookup maps for speed.
  Future<bool> _importM3u(
    File m3uFile,
    String rootPath,
    Map<String, Song> pathMap,
    Map<String, Song> fileNameMap,
  ) async {
    final lines = await m3uFile.readAsLines();
    final playlistName = m3uFile.path
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.(m3u8?|M3U8?)$'), '');

    // Skip if already exists
    final existingPlaylists = await _db.getAllPlaylists();
    if (existingPlaylists.any((p) => p.title == playlistName)) return false;

    final playlistId =
        await _db.insertPlaylist(Playlist(title: playlistName));
    if (playlistId <= 0) return false;

    int assigned = 0;
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Resolve path
      String resolvedPath;
      if (line.startsWith('/')) {
        resolvedPath = line;
      } else {
        resolvedPath = '${m3uFile.parent.path}/$line';
      }
      resolvedPath = resolvedPath.replaceAll('\\', '/');

      // Fast lookup by path
      Song? song = pathMap[resolvedPath];

      // Fallback: lookup by filename
      if (song == null) {
        final fn = resolvedPath.split('/').last.toLowerCase();
        song = fileNameMap[fn];
      }

      if (song != null && song.id != null) {
        await _db.setSongFilter(SongFilter(
          playlistId: playlistId,
          songId: song.id!,
          hasTitle: true,
        ));
        assigned++;
      }
    }

    // Delete empty playlists
    if (assigned == 0) {
      await _db.deletePlaylist(playlistId);
      return false;
    }
    return true;
  }

  /// Remove songs whose files no longer exist.
  Future<int> pruneDeletedFiles() async {
    final allSongs = await _db.getAllSongs();
    int pruned = 0;
    for (final song in allSongs) {
      if (!await File(song.filePath).exists()) {
        if (song.id != null) {
          await _db.deleteSong(song.id!);
          pruned++;
        }
      }
    }
    return pruned;
  }
}

class _ParsedFileName {
  final String title;
  final String? artist;
  _ParsedFileName({required this.title, this.artist});
}

class ScanResult {
  final int songsImported;
  final int songsSkipped;
  final int totalAudioFiles;
  final int playlistsImported;
  final int totalPlaylists;
  final String? error;

  ScanResult({
    this.songsImported = 0,
    this.songsSkipped = 0,
    this.totalAudioFiles = 0,
    this.playlistsImported = 0,
    this.totalPlaylists = 0,
    this.error,
  });

  @override
  String toString() {
    if (error != null) return 'Error: $error';
    return 'Found $totalAudioFiles audio files. '
        'Imported $songsImported new songs ($songsSkipped already in library). '
        '$playlistsImported of $totalPlaylists playlists imported.';
  }
}
