import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as as_pkg;
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'pig_web_service.dart';

/// Playback repeat modes — matches PIGv4's off/all/one.
enum PigRepeatMode { off, all, one }

/// The audio handler that integrates with the system media session.
/// Bluetooth, Android Auto, lock screen, notifications all talk to this.
class PigAudioHandler extends as_pkg.BaseAudioHandler with as_pkg.SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  PigWebService? pigWebService;

  List<Song> _playlist = [];
  List<Song> _originalPlaylist = [];
  int _currentIndex = -1;
  bool _shuffle = false;
  PigRepeatMode _repeatMode = PigRepeatMode.off;
  Song? _currentSong;
  Uint8List? _currentAlbumArt;
  Uri? _artUri;
  List<String> _currentPlaylists = [];
  bool _keepScreenOn = false;

  // Callback to notify the ChangeNotifier wrapper
  VoidCallback? onStateChanged;

  // Public getters
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isShuffle => _shuffle;
  PigRepeatMode get repeatMode => _repeatMode;
  Song? get currentSong => _currentSong;
  double get volume => _player.volume;
  Duration get position => _player.position;
  Duration get dur => _player.duration ?? Duration.zero;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Uint8List? get currentAlbumArt => _currentAlbumArt;
  List<String> get currentPlaylists => _currentPlaylists;
  bool get keepScreenOn => _keepScreenOn;
  bool get isPlaying => _player.playing;

  PigAudioHandler() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
      _broadcastState();
      onStateChanged?.call();
    });
  }

  /// Broadcast playback state to the system.
  void _broadcastState() {
    playbackState.add(
      as_pkg.PlaybackState(
        controls: [
          as_pkg.MediaControl.skipToPrevious,
          if (_player.playing)
            as_pkg.MediaControl.pause
          else
            as_pkg.MediaControl.play,
          as_pkg.MediaControl.stop,
          as_pkg.MediaControl.skipToNext,
        ],
        systemActions: const {
          as_pkg.MediaAction.seek,
          as_pkg.MediaAction.seekForward,
          as_pkg.MediaAction.seekBackward,
          as_pkg.MediaAction.skipToNext,
          as_pkg.MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _mapState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
      ),
    );
  }

  as_pkg.AudioProcessingState _mapState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return as_pkg.AudioProcessingState.idle;
      case ProcessingState.loading:
        return as_pkg.AudioProcessingState.loading;
      case ProcessingState.buffering:
        return as_pkg.AudioProcessingState.buffering;
      case ProcessingState.ready:
        return as_pkg.AudioProcessingState.ready;
      case ProcessingState.completed:
        return as_pkg.AudioProcessingState.completed;
    }
  }

  void _broadcastMediaItem() {
    if (_currentSong == null) return;
    final song = _currentSong!;
    debugPrint('PIG: broadcastMediaItem title=${song.displayTitle} artist=${song.displayArtist} artUri=$_artUri');
    mediaItem.add(
      as_pkg.MediaItem(
        id: song.filePath,
        title: song.displayTitle,
        artist: song.displayArtist,
        album: song.displayAlbum,
        duration: _player.duration,
        genre: song.genre,
        artUri: _artUri,
        displayTitle: song.displayTitle,
        displaySubtitle: song.displayArtist,
        displayDescription: song.displayAlbum,
        rating: null,
        extras: null,
      ),
    );
  }

  // ── Playlist management ──

  void setPlaylist(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    _originalPlaylist = List.from(songs);
    _playlist = List.from(songs);
    if (_shuffle) _shufflePlaylist();
    _currentIndex = startIndex;

    // Update queue for Android Auto browsing
    queue.add(
      _playlist
          .map(
            (s) => as_pkg.MediaItem(
              id: s.filePath,
              title: s.displayTitle,
              artist: s.displayArtist,
              album: s.displayAlbum,
              genre: s.genre,
              artUri: null,
              displayTitle: s.displayTitle,
              displaySubtitle: s.displayArtist,
              displayDescription: s.displayAlbum,
              duration: null,
              rating: null,
              extras: null,
            ),
          )
          .toList(),
    );

    if (autoPlay && _playlist.isNotEmpty) {
      _playSongAtIndex(_currentIndex);
    }
  }

  Future<void> _playSongAtIndex(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    final song = _playlist[index];
    _currentSong = song;
    debugPrint('PIG: playing index=$index title=${song.displayTitle}');
    await _setAlbumArt(null);
    _currentPlaylists = [];
    onStateChanged?.call();

    try {
      if (song.filePath.startsWith('web://')) {
        final pieceId = int.tryParse(song.filePath.replaceFirst('web://', ''));
        if (pieceId != null && pigWebService != null) {
          final url = pigWebService!.getStreamUrl(pieceId);
          await _player.setUrl(url, headers: pigWebService!.authHeaders);
        }
      } else {
        await _player.setFilePath(song.filePath);
      }
      _player.play();
      _broadcastMediaItem();
      _loadSongExtras(song);
    } catch (e) {
      debugPrint('Error playing ${song.filePath}: $e');
    }
    onStateChanged?.call();
  }

  Future<void> _loadSongExtras(Song song) async {
    if (song.id == null || song.filePath.startsWith('web://')) return;
    final db = DatabaseService();

    _currentPlaylists = await db.getPlaylistNamesForSong(song.id!);

    final cached = await db.getAlbumArt(song.id!);
    if (cached != null) {
      await _setAlbumArt(Uint8List.fromList(cached));
      _broadcastMediaItem();
      onStateChanged?.call();
      return;
    }

    final checked = await db.isAlbumArtChecked(song.id!);
    if (checked) {
      onStateChanged?.call();
      return;
    }

    try {
      final file = File(song.filePath);
      if (await file.exists()) {
        final metadata = readMetadata(file, getImage: true);
        if (metadata.pictures.isNotEmpty) {
          final artBytes = metadata.pictures.first.bytes;
          await _setAlbumArt(Uint8List.fromList(artBytes));
          await db.setAlbumArt(song.id!, artBytes);
          _broadcastMediaItem();
          onStateChanged?.call();
          return;
        }
      }
    } catch (_) {}

    // Step 2: Try MusicBrainz / Cover Art Archive (actual album cover)
    if (song.artist != null && song.artist!.isNotEmpty) {
      try {
        final artBytes = await _fetchCoverArtArchive(song.artist!, song.album);
        if (artBytes != null) {
          await _setAlbumArt(Uint8List.fromList(artBytes));
          await db.setAlbumArt(song.id!, artBytes);
          _broadcastMediaItem();
          onStateChanged?.call();
          return;
        }
      } catch (_) {}
    }

    // Step 3: Fallback — try Wikipedia artist image
    if (_currentSong?.artist != null && _currentSong!.artist!.isNotEmpty) {
      try {
        final artBytes = await _fetchWikipediaArtistImage(
          _currentSong!.artist!,
        );
        if (artBytes != null) {
          await _setAlbumArt(Uint8List.fromList(artBytes));
          await db.setAlbumArt(song.id!, artBytes);
          _broadcastMediaItem();
          onStateChanged?.call();
          return;
        }
      } catch (_) {}
    }

    await db.setAlbumArt(song.id!, null);
    onStateChanged?.call();
  }

  Future<void> _setAlbumArt(Uint8List? bytes) async {
    _currentAlbumArt = bytes;
    if (bytes != null) {
      final tempDir = await getTemporaryDirectory();
      final artFile = File('${tempDir.path}/album_art.jpg');
      await artFile.writeAsBytes(bytes);
      _artUri = Uri.file(artFile.path);
    } else {
      _artUri = null;
    }
  }

  /// Fetch artist image from Wikipedia API.
  Future<List<int>?> _fetchWikipediaArtistImage(String artist) async {
    // Try the artist name directly, then with common disambiguation suffixes
    final searchNames = [
      artist.replaceAll(' ', '_'),
      '${artist.replaceAll(' ', '_')}_(band)',
      '${artist.replaceAll(' ', '_')}_(singer)',
      '${artist.replaceAll(' ', '_')}_(musician)',
      '${artist.replaceAll(' ', '_')}_(music)',
    ];

    for (final searchName in searchNames) {
      final result = await _tryWikipediaPage(searchName);
      if (result != null) return result;
    }
    return null;
  }

  Future<List<int>?> _tryWikipediaPage(String pageName) async {
    try {
      final client = HttpClient();
      final apiUrl = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/$pageName',
      );

      final request = await client.getUrl(apiUrl);
      request.headers.set('User-Agent', 'PIGMobile/1.0');
      final response = await request.close();

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final data = _parseJson(body);

      // Skip disambiguation pages
      if (data != null && data['type'] == 'disambiguation') {
        client.close();
        return null;
      }

      String? imageUrl;
      if (data != null && data['thumbnail'] != null) {
        imageUrl = data['thumbnail']['source'];
      } else if (data != null && data['originalimage'] != null) {
        imageUrl = data['originalimage']['source'];
      }

      if (imageUrl == null || imageUrl.isEmpty) {
        client.close();
        return null;
      }

      // Download the image
      final imgRequest = await client.getUrl(Uri.parse(imageUrl));
      imgRequest.headers.set('User-Agent', 'PIGMobile/1.0');
      final imgResponse = await imgRequest.close();

      if (imgResponse.statusCode != 200) {
        client.close();
        return null;
      }

      final bytes = <int>[];
      await for (final chunk in imgResponse) {
        bytes.addAll(chunk);
        if (bytes.length > 500000) break;
      }
      client.close();

      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Fetch album cover from MusicBrainz + Cover Art Archive.
  /// Searches by artist + album, then grabs the front cover image.
  Future<List<int>?> _fetchCoverArtArchive(String artist, String? album) async {
    if (album == null || album.isEmpty) return null;

    try {
      final client = HttpClient();

      // Search MusicBrainz for the release
      final query =
          'artist:${Uri.encodeComponent(artist)}+release:${Uri.encodeComponent(album)}';
      final searchUrl = Uri.parse(
        'https://musicbrainz.org/ws/2/release/?query=$query&fmt=json&limit=1',
      );

      final request = await client.getUrl(searchUrl);
      request.headers.set('User-Agent', 'PIGMobile/1.0 (pig-music-player)');
      final response = await request.close();

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final data = _parseJson(body);
      if (data == null) {
        client.close();
        return null;
      }

      final releases = data['releases'] as List?;
      if (releases == null || releases.isEmpty) {
        client.close();
        return null;
      }

      final releaseId = releases[0]['id'] as String?;
      if (releaseId == null || releaseId.isEmpty) {
        client.close();
        return null;
      }

      // Get the front cover from Cover Art Archive
      final coverUrl = Uri.parse(
        'https://coverartarchive.org/release/$releaseId/front-250',
      );

      final coverRequest = await client.getUrl(coverUrl);
      coverRequest.headers.set('User-Agent', 'PIGMobile/1.0');
      coverRequest.followRedirects = true;
      final coverResponse = await coverRequest.close();

      if (coverResponse.statusCode != 200 && coverResponse.statusCode != 307) {
        client.close();
        return null;
      }

      // Handle redirect
      if (coverResponse.statusCode == 307) {
        final redirectUrl = coverResponse.headers.value('location');
        if (redirectUrl == null) {
          client.close();
          return null;
        }
        final redirectRequest = await client.getUrl(Uri.parse(redirectUrl));
        redirectRequest.headers.set('User-Agent', 'PIGMobile/1.0');
        final redirectResponse = await redirectRequest.close();
        if (redirectResponse.statusCode != 200) {
          client.close();
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in redirectResponse) {
          bytes.addAll(chunk);
          if (bytes.length > 500000) break;
        }
        client.close();
        return bytes.isNotEmpty ? bytes : null;
      }

      final bytes = <int>[];
      await for (final chunk in coverResponse) {
        bytes.addAll(chunk);
        if (bytes.length > 500000) break;
      }
      client.close();
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Simple JSON parser using dart:convert.
  Map<String, dynamic>? _parseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── System transport controls ──

  @override
  Future<void> play() async {
    if (_currentSong == null && _playlist.isNotEmpty) {
      await _playSongAtIndex(0);
    } else {
      _player.play();
    }
  }

  @override
  Future<void> pause() async => await _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;
    if (_repeatMode == PigRepeatMode.one) {
      await _player.seek(Duration.zero);
      _player.play();
      return;
    }
    _currentIndex++;
    if (_currentIndex >= _playlist.length) {
      if (_repeatMode == PigRepeatMode.all) {
        _currentIndex = 0;
        if (_shuffle) _shufflePlaylist();
      } else {
        _currentIndex = _playlist.length - 1;
        await stop();
        return;
      }
    }
    await _playSongAtIndex(_currentIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    await _playSongAtIndex(_currentIndex);
  }

  @override
  Future<void> seek(Duration position) async => await _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _playlist.length) {
      await _playSongAtIndex(index);
    }
  }

  // ── Custom methods for UI ──

  Future<void> toggle() async {
    if (_currentSong == null && _playlist.isNotEmpty) {
      await _playSongAtIndex(0);
    } else if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> setVolume(double vol) async =>
      await _player.setVolume(vol.clamp(0.0, 1.0));

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) {
      _shufflePlaylist();
    } else {
      _playlist = List.from(_originalPlaylist);
      if (_currentSong != null) {
        _currentIndex = _playlist.indexWhere((s) => s.id == _currentSong!.id);
      }
    }
    onStateChanged?.call();
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case PigRepeatMode.off:
        _repeatMode = PigRepeatMode.all;
      case PigRepeatMode.all:
        _repeatMode = PigRepeatMode.one;
      case PigRepeatMode.one:
        _repeatMode = PigRepeatMode.off;
    }
    onStateChanged?.call();
  }

  void removeFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    _playlist.removeAt(index);
    if (index < _currentIndex) _currentIndex--;
    onStateChanged?.call();
  }

  void setKeepScreenOn(bool value) {
    _keepScreenOn = value;
    if (value) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _shufflePlaylist() {
    final current = _currentSong;
    _playlist.shuffle(Random());
    if (current != null) {
      _playlist.removeWhere((s) => s.id == current.id);
      _playlist.insert(0, current);
      _currentIndex = 0;
    }
  }
}

/// ChangeNotifier wrapper for Provider — bridges PigAudioHandler with Flutter widgets.
class AudioService extends ChangeNotifier {
  late PigAudioHandler _handler;
  bool _initialized = false;
  List<Song>? _pendingPlaylist;
  int _pendingStartIndex = 0;
  bool _pendingAutoPlay = true;


  bool get initialized => _initialized;
  List<Song> get playlist => _initialized ? _handler.playlist : [];
  int get currentIndex => _initialized ? _handler.currentIndex : -1;
  bool get shuffle => _initialized ? _handler.isShuffle : false;
  PigRepeatMode get repeatMode =>
      _initialized ? _handler.repeatMode : PigRepeatMode.off;
  Song? get currentSong => _initialized ? _handler.currentSong : null;
  bool get isPlaying => _initialized ? _handler.isPlaying : false;
  Duration get position => _initialized ? _handler.position : Duration.zero;
  Duration get duration => _initialized ? _handler.dur : Duration.zero;
  double get volume => _initialized ? _handler.volume : 1.0;
  Stream<Duration> get positionStream =>
      _initialized ? _handler.positionStream : const Stream.empty();
  Stream<PlayerState> get playerStateStream =>
      _initialized ? _handler.playerStateStream : const Stream.empty();
  Uint8List? get currentAlbumArt =>
      _initialized ? _handler.currentAlbumArt : null;
  List<String> get currentPlaylists =>
      _initialized ? _handler.currentPlaylists : [];
  bool get keepScreenOn => _initialized ? _handler.keepScreenOn : false;

  AudioService() {
    _handler = PigAudioHandler();
    _handler.onStateChanged = () => notifyListeners();
  }

  /// Called from main() AFTER runApp — fixes splash hang on some Android versions.
  Future<void> initMediaSession() async {
    try {
      final registeredHandler = await as_pkg.AudioService.init(
        builder: () => _handler,
        config: const as_pkg.AudioServiceConfig(
          androidNotificationChannelId: 'com.pig.pig_mobile.audio',
          androidNotificationChannelName: 'PIG Music',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      // MUST use the returned handler — it's the one connected to the media session.
      _handler = registeredHandler as PigAudioHandler;
      _handler.onStateChanged = () => notifyListeners();
      debugPrint('PIG: media session initialized OK, handler=$registeredHandler');
    } catch (e) {
      debugPrint('PIG: AudioService.init FAILED: $e');
    }

    _initialized = true;

    if (_pendingPlaylist != null) {
      _handler.setPlaylist(
        _pendingPlaylist!,
        startIndex: _pendingStartIndex,
        autoPlay: _pendingAutoPlay,
      );
      _pendingPlaylist = null;
    }
    notifyListeners();
  }

  void setPlaylist(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    if (!_initialized) {
      _pendingPlaylist = songs;
      _pendingStartIndex = startIndex;
      _pendingAutoPlay = autoPlay;
      return;
    }
    _handler.setPlaylist(songs, startIndex: startIndex, autoPlay: autoPlay);
    notifyListeners();
  }

  Future<void> toggle() async {
    if (!_initialized) return;
    await _handler.toggle();
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _handler.stop();
    notifyListeners();
  }

  Future<void> next() async {
    if (!_initialized) return;
    await _handler.skipToNext();
    notifyListeners();
  }

  Future<void> prev() async {
    if (!_initialized) return;
    await _handler.skipToPrevious();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (!_initialized) return;
    await _handler.seek(position);
  }

  Future<void> setVolume(double vol) async {
    if (!_initialized) return;
    await _handler.setVolume(vol);
    notifyListeners();
  }

  void toggleShuffle() {
    if (!_initialized) return;
    _handler.toggleShuffle();
    notifyListeners();
  }

  void toggleRepeat() {
    if (!_initialized) return;
    _handler.toggleRepeat();
    notifyListeners();
  }

  void removeFromPlaylist(int index) {
    if (!_initialized) return;
    _handler.removeFromPlaylist(index);
    notifyListeners();
  }

  void setKeepScreenOn(bool value) {
    if (!_initialized) return;
    _handler.setKeepScreenOn(value);
    notifyListeners();
  }

  void setPigWebService(PigWebService? service) {
    if (!_initialized) return;
    _handler.pigWebService = service;
  }
}
