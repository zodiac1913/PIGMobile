import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as audio_svc;
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import 'database_service.dart';

/// Playback repeat modes — matches PIGv4's off/all/one.
enum PigRepeatMode { off, all, one }

/// Audio player service with media session for Bluetooth/Android Auto/CarPlay.
class AudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  late final audio_svc.AudioHandler _audioHandler;
  bool _handlerInitialized = false;

  List<Song> _playlist = [];
  List<Song> _originalPlaylist = [];
  int _currentIndex = -1;
  bool _shuffle = false;
  PigRepeatMode _repeatMode = PigRepeatMode.off;
  Song? _currentSong;
  bool _isLoading = false;
  Uint8List? _currentAlbumArt;
  List<String> _currentPlaylists = [];

  // Public getters
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get shuffle => _shuffle;
  PigRepeatMode get repeatMode => _repeatMode;
  Song? get currentSong => _currentSong;
  bool get isLoading => _isLoading;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  double get volume => _player.volume;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Uint8List? get currentAlbumArt => _currentAlbumArt;
  List<String> get currentPlaylists => _currentPlaylists;

  AudioService() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      _updateMediaSession();
    });
    _initAudioHandler();
  }

  Future<void> _initAudioHandler() async {
    try {
      _audioHandler = await audio_svc.AudioService.init(
        builder: () => _PigAudioHandler(this),
        config: const audio_svc.AudioServiceConfig(
          androidNotificationChannelId: 'com.pig.pig_mobile.audio',
          androidNotificationChannelName: 'PIG Music',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      _handlerInitialized = true;
    } catch (e) {
      debugPrint('Audio handler init failed: $e');
    }
  }

  void _updateMediaSession() {
    if (!_handlerInitialized || _currentSong == null) return;
    try {
      final song = _currentSong!;
      final handler = _audioHandler as _PigAudioHandler;
      handler.setMediaItem(audio_svc.MediaItem(
        id: song.filePath,
        title: song.displayTitle,
        artist: song.displayArtist,
        album: song.displayAlbum,
        duration: _player.duration,
        genre: song.genre,
      ));
      handler.setPlaybackState(audio_svc.PlaybackState(
        controls: [
          audio_svc.MediaControl.skipToPrevious,
          _player.playing ? audio_svc.MediaControl.pause : audio_svc.MediaControl.play,
          audio_svc.MediaControl.stop,
          audio_svc.MediaControl.skipToNext,
        ],
        systemActions: const {
          audio_svc.MediaAction.seek,
          audio_svc.MediaAction.seekForward,
          audio_svc.MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: audio_svc.AudioProcessingState.ready,
        playing: _player.playing,
        updatePosition: _player.position,
        speed: 1.0,
      ));
    } catch (e) {
      debugPrint('Media session update failed: $e');
    }
  }

  /// Load a playlist and optionally start playing.
  void setPlaylist(List<Song> songs,
      {int startIndex = 0, bool autoPlay = true}) {
    _originalPlaylist = List.from(songs);
    _playlist = List.from(songs);
    if (_shuffle) _shufflePlaylist();
    _currentIndex = startIndex;
    if (autoPlay && _playlist.isNotEmpty) {
      playSong(_playlist[_currentIndex]);
    }
    notifyListeners();
  }

  /// Play a specific song.
  Future<void> playSong(Song song) async {
    _currentSong = song;
    _isLoading = true;
    _currentAlbumArt = null;
    _currentPlaylists = [];
    notifyListeners();

    try {
      await _player.setFilePath(song.filePath);
      await _player.play();
      final idx = _playlist.indexWhere((s) => s.id == song.id);
      if (idx >= 0) _currentIndex = idx;

      // Load album art and playlist info in background
      _loadSongExtras(song);
    } catch (e) {
      debugPrint('Error playing ${song.filePath}: $e');
    }

    _isLoading = false;
    notifyListeners();
    _updateMediaSession();
  }

  /// Load album art from embedded tags and playlist names.
  Future<void> _loadSongExtras(Song song) async {
    if (song.id == null) return;
    final db = DatabaseService();

    // Load playlist names
    _currentPlaylists = await db.getPlaylistNamesForSong(song.id!);

    // Try cached album art first
    final cached = await db.getAlbumArt(song.id!);
    if (cached != null) {
      _currentAlbumArt = Uint8List.fromList(cached);
      notifyListeners();
      return;
    }

    // Check if already looked up
    final checked = await db.isAlbumArtChecked(song.id!);
    if (checked) {
      notifyListeners();
      return;
    }

    // Try to extract from the file's embedded tags
    try {
      final file = File(song.filePath);
      if (await file.exists()) {
        final metadata = readMetadata(file, getImage: true);
        if (metadata.pictures.isNotEmpty) {
          final artBytes = metadata.pictures.first.bytes;
          _currentAlbumArt = Uint8List.fromList(artBytes);
          await db.setAlbumArt(song.id!, artBytes);
          notifyListeners();
          return;
        }
      }
    } catch (_) {}

    // Mark as checked (no art found)
    await db.setAlbumArt(song.id!, null);
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_currentSong == null) {
      if (_playlist.isNotEmpty) {
        _currentIndex = 0;
        await playSong(_playlist[0]);
      }
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    notifyListeners();
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    if (_repeatMode == PigRepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
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
    await playSong(_playlist[_currentIndex]);
  }

  Future<void> prev() async {
    if (_playlist.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    _currentIndex =
        (_currentIndex - 1 + _playlist.length) % _playlist.length;
    await playSong(_playlist[_currentIndex]);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double vol) async {
    await _player.setVolume(vol.clamp(0.0, 1.0));
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) {
      _shufflePlaylist();
    } else {
      _playlist = List.from(_originalPlaylist);
      if (_currentSong != null) {
        _currentIndex =
            _playlist.indexWhere((s) => s.id == _currentSong!.id);
      }
    }
    notifyListeners();
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case PigRepeatMode.off:
        _repeatMode = PigRepeatMode.all;
        break;
      case PigRepeatMode.all:
        _repeatMode = PigRepeatMode.one;
        break;
      case PigRepeatMode.one:
        _repeatMode = PigRepeatMode.off;
        break;
    }
    notifyListeners();
  }

  /// Remove a song from the playlist by index (for the "X" button on upcoming).
  void removeFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    _playlist.removeAt(index);
    // Adjust current index if needed
    if (index < _currentIndex) {
      _currentIndex--;
    }
    notifyListeners();
  }

  bool _keepScreenOn = false;
  bool get keepScreenOn => _keepScreenOn;

  void setKeepScreenOn(bool value) {
    _keepScreenOn = value;
    if (value) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    notifyListeners();
  }

  void _shufflePlaylist() {
    final current = _currentSong;
    _playlist.shuffle(Random());
    if (current != null) {
      _playlist.removeWhere((s) => s.id == current.id);
      _playlist.insert(0, current);
      _currentIndex = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

/// Audio handler for media session — routes Bluetooth/Auto/CarPlay controls.
class _PigAudioHandler extends audio_svc.BaseAudioHandler
    with audio_svc.SeekHandler {
  final AudioService _service;

  _PigAudioHandler(this._service);

  void setMediaItem(audio_svc.MediaItem item) {
    mediaItem.add(item);
  }

  void setPlaybackState(audio_svc.PlaybackState state) {
    playbackState.add(state);
  }

  @override
  Future<void> play() => _service.toggle();

  @override
  Future<void> pause() => _service.toggle();

  @override
  Future<void> stop() => _service.stop();

  @override
  Future<void> skipToNext() => _service.next();

  @override
  Future<void> skipToPrevious() => _service.prev();

  @override
  Future<void> seek(Duration position) => _service.seek(position);
}

/// Platform init helper.
class AudioServicePlatform {
  static Future<audio_svc.AudioHandler> init({
    required audio_svc.AudioHandler Function() builder,
    audio_svc.AudioServiceConfig config = const audio_svc.AudioServiceConfig(),
  }) async {
    return await audio_svc.AudioService.init(
      builder: builder,
      config: config,
    );
  }
}
