import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/playlist.dart';
import 'database_service.dart';

/// Service for communicating with PIG Web (PIGv4 server).
/// Handles auth, browsing, streaming, and downloading.
class PigWebService {
  String? _baseUrl;
  String? _token;
  String? _username;

  bool get isConfigured => _baseUrl != null && _baseUrl!.isNotEmpty;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String? get baseUrl => _baseUrl;
  String? get username => _username;

  void configure(String baseUrl) {
    var normalized = baseUrl.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.startsWith(RegExp(r'https?://'))) {
      normalized = 'https://$normalized';
    }
    _baseUrl = normalized;
  }

  /// Login and get a bearer token.
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    String deviceName,
  ) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'deviceName': deviceName,
      }),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      _token = data['token'];
      _username = data['username'];
      return data;
    } else {
      final error = jsonDecode(resp.body);
      throw Exception(error['error'] ?? 'Login failed');
    }
  }

  /// Set token directly (for restoring saved session).
  void setToken(String token, String username) {
    _token = token;
    _username = username;
  }

  void logout() {
    _token = null;
    _username = null;
  }

  Map<String, String> get _headers => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Get filter lists (playlists, folders, genres, artists).
  Future<List<dynamic>> getFilters(String type) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/Player/Filters?type=$type'),
      headers: _headers,
    );
    if (resp.statusCode != 200) throw Exception('Failed to load $type filters');
    return jsonDecode(resp.body);
  }

  /// Get playlists (returns list of {listId, title}).
  Future<List<Playlist>> getPlaylists() async {
    final data = await getFilters('playlists');
    return data
        .map((d) => Playlist(id: d['listId'], title: d['title']))
        .toList();
  }

  /// Get folders list.
  Future<List<String>> getFolders() async {
    final data = await getFilters('folders');
    return data.cast<String>();
  }

  /// Get genres list.
  Future<List<String>> getGenres() async {
    final data = await getFilters('genres');
    return data.cast<String>();
  }

  /// Get artists list.
  Future<List<String>> getArtists() async {
    final data = await getFilters('artists');
    return data.cast<String>();
  }

  /// Browse songs with filters (same params as PIGv4 Player/Browse).
  Future<List<Song>> browseSongs({
    List<int>? listIds,
    List<String>? folders,
    List<String>? genres,
    List<String>? artists,
    int pageSize = 10000,
  }) async {
    var url = '$_baseUrl/Player/Browse?pageSize=$pageSize';
    if (listIds != null) {
      for (final id in listIds) {
        url += '&listIds=$id';
      }
    }
    if (folders != null) {
      for (final f in folders) {
        url += '&folders=${Uri.encodeComponent(f)}';
      }
    }
    if (genres != null) {
      for (final g in genres) {
        url += '&genres=${Uri.encodeComponent(g)}';
      }
    }
    if (artists != null) {
      for (final a in artists) {
        url += '&artists=${Uri.encodeComponent(a)}';
      }
    }

    final resp = await http.get(Uri.parse(url), headers: _headers);
    if (resp.statusCode != 200) throw Exception('Browse failed');

    final data = jsonDecode(resp.body);
    final songs = (data['songs'] as List)
        .map(
          (s) => Song(
            id: s['pieceId'],
            filePath: 'web://${s['pieceId']}', // Virtual path for web songs
            title: s['title'],
            artist: s['artist'],
            album: s['album'],
            genre: s['genre'],
            year: s['year'],
            durationMs: s['seconds'] != null
                ? (s['seconds'] as int) * 1000
                : null,
            sourceFolder: s['sourceFolder'],
          ),
        )
        .toList();
    return songs;
  }

  /// Get the streaming URL for a song.
  String getStreamUrl(int pieceId) {
    return '$_baseUrl/Player/Stream?id=$pieceId';
  }

  /// Get album art URL for a song.
  String getAlbumArtUrl(int pieceId) {
    return '$_baseUrl/Player/AlbumArt?id=$pieceId';
  }

  /// Get auth headers for streaming (needed by just_audio).
  Map<String, String> get authHeaders => _headers;

  /// Download a song MP3 to the device music folder.
  /// Returns the local file path on success.
  Future<String?> downloadSong(
    int pieceId, {
    required String musicFolder,
    String? sourceFolder,
    String? fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      // Determine target directory
      String targetDir = musicFolder;
      if (sourceFolder != null && sourceFolder.isNotEmpty) {
        targetDir = '$musicFolder/$sourceFolder';
      }
      final dir = Directory(targetDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Get song details for filename if not provided
      if (fileName == null) {
        final detailResp = await http.get(
          Uri.parse('$_baseUrl/Player/BrowseById?id=$pieceId'),
          headers: _headers,
        );
        if (detailResp.statusCode == 200) {
          final detail = jsonDecode(detailResp.body);
          if (detail['song'] != null) {
            final artist = detail['song']['artist'] ?? 'Unknown';
            final title = detail['song']['title'] ?? 'Unknown';
            fileName = '$artist - $title.mp3';
          }
        }
        fileName ??= 'song_$pieceId.mp3';
      }

      // Clean filename
      fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = '$targetDir/$fileName';

      // Check if already downloaded
      if (await File(filePath).exists()) return filePath;

      // Download
      final request = http.Request(
        'GET',
        Uri.parse('$_baseUrl/Songs/Download?id=$pieceId'),
      );
      request.headers.addAll(_headers);
      final streamedResp = await request.send();

      if (streamedResp.statusCode != 200) return null;

      final totalBytes = streamedResp.contentLength ?? -1;
      int received = 0;
      final sink = File(filePath).openWrite();

      await for (final chunk in streamedResp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes);
      }
      await sink.close();

      return filePath;
    } catch (e) {
      debugPrint('Download failed for pieceId $pieceId: $e');
      return null;
    }
  }

  /// Download multiple songs, importing them into the local database.
  Future<int> downloadAndImportSongs(
    List<Song> songs, {
    required String musicFolder,
    required DatabaseService db,
    void Function(String status, int current, int total)? onProgress,
  }) async {
    int downloaded = 0;
    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final pieceId = song.id;
      if (pieceId == null) continue;

      onProgress?.call(
        '${song.displayArtist} - ${song.displayTitle}',
        i + 1,
        songs.length,
      );

      final filePath = await downloadSong(
        pieceId,
        musicFolder: musicFolder,
        sourceFolder: song.sourceFolder,
      );

      if (filePath != null) {
        // Import into local database if not already there
        final existing = await db.getSongByPath(filePath);
        if (existing == null) {
          await db.insertSong(
            song.copyWith(
              id: null, // Let local DB assign ID
              filePath: filePath,
            ),
          );
        }
        downloaded++;
      }
    }
    return downloaded;
  }
}
