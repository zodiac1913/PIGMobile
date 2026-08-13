import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

/// Persists app settings (PIG Web URL, token, preferences).
class SettingsService {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  // Cached values
  String? _pigWebUrl;
  String? _pigWebToken;
  String? _pigWebUsername;
  bool _downloadWebMusic = false;
  bool _onlyDownloadOnWifi = true;
  String _musicPath = '/storage/emulated/0/Music';

  String? get pigWebUrl => _pigWebUrl;
  String? get pigWebToken => _pigWebToken;
  String? get pigWebUsername => _pigWebUsername;
  bool get downloadWebMusic => _downloadWebMusic;
  bool get onlyDownloadOnWifi => _onlyDownloadOnWifi;
  String get musicPath => _musicPath;

  // Playback preferences
  bool _shuffleOn = true;
  bool _repeatOn = true;
  bool _screenOn = false;
  bool _playAllOnStart = false;
  bool _playSelectOnStart = false;

  bool get shuffleOn => _shuffleOn;
  bool get repeatOn => _repeatOn;
  bool get screenOn => _screenOn;
  bool get playAllOnStart => _playAllOnStart;
  bool get playSelectOnStart => _playSelectOnStart;

  /// Load settings from the database.
  Future<void> load() async {
    final db = await DatabaseService().database;
    // Ensure settings table exists
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    _pigWebUrl = await _get(db, 'pigWebUrl');
    _pigWebToken = await _get(db, 'pigWebToken');
    _pigWebUsername = await _get(db, 'pigWebUsername');
    _downloadWebMusic = (await _get(db, 'downloadWebMusic')) == '1';
    _onlyDownloadOnWifi = (await _get(db, 'onlyDownloadOnWifi')) != '0';
    _musicPath = (await _get(db, 'musicPath')) ?? '/storage/emulated/0/Music';
    _shuffleOn = (await _get(db, 'shuffleOn')) != '0';
    _repeatOn = (await _get(db, 'repeatOn')) != '0';
    _screenOn = (await _get(db, 'screenOn')) == '1';
    _playAllOnStart = (await _get(db, 'playAllOnStart')) == '1';
    _playSelectOnStart = (await _get(db, 'playSelectOnStart')) == '1';
  }

  Future<void> setPigWebUrl(String? url) async {
    _pigWebUrl = url;
    await _set('pigWebUrl', url);
  }

  Future<void> setPigWebToken(String? token) async {
    _pigWebToken = token;
    await _set('pigWebToken', token);
  }

  Future<void> setPigWebUsername(String? username) async {
    _pigWebUsername = username;
    await _set('pigWebUsername', username);
  }

  Future<void> setDownloadWebMusic(bool value) async {
    _downloadWebMusic = value;
    await _set('downloadWebMusic', value ? '1' : '0');
  }

  Future<void> setOnlyDownloadOnWifi(bool value) async {
    _onlyDownloadOnWifi = value;
    await _set('onlyDownloadOnWifi', value ? '1' : '0');
  }

  Future<void> setMusicPath(String path) async {
    _musicPath = path;
    await _set('musicPath', path);
  }

  Future<void> setShuffleOn(bool value) async {
    _shuffleOn = value;
    await _set('shuffleOn', value ? '1' : '0');
  }

  Future<void> setRepeatOn(bool value) async {
    _repeatOn = value;
    await _set('repeatOn', value ? '1' : '0');
  }

  Future<void> setScreenOn(bool value) async {
    _screenOn = value;
    await _set('screenOn', value ? '1' : '0');
  }

  Future<void> setPlayAllOnStart(bool value) async {
    _playAllOnStart = value;
    await _set('playAllOnStart', value ? '1' : '0');
  }

  Future<void> setPlaySelectOnStart(bool value) async {
    _playSelectOnStart = value;
    await _set('playSelectOnStart', value ? '1' : '0');
  }

  Future<String?> _get(Database db, String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _set(String key, String? value) async {
    final db = await DatabaseService().database;
    if (value == null) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('app_settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
