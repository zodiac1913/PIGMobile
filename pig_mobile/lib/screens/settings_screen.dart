import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../services/database_service.dart';
import '../services/scanner_service.dart';
import '../services/pig_web_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../version.dart';

/// Settings screen — scan music folder, prune deleted files, view stats.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _musicPath = '';
  int _songCount = 0;
  bool _scanning = false;
  String _scanStatus = '';
  int _scanProgress = 0;
  int _scanTotal = 0;

  // PIG Web settings
  final _webUrlController = TextEditingController();
  final _webUsernameController = TextEditingController();
  final _webPasswordController = TextEditingController();
  bool _webLoggedIn = false;
  String? _webDisplayName;
  bool _downloadWebMusic = false;
  bool _onlyDownloadOnWifi = true;
  String _webLoginStatus = '';

  final PigWebService _webService = PigWebService();
  final SettingsService _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadWebSettings();
  }

  Future<void> _loadWebSettings() async {
    await _settings.load();
    setState(() {
      _webUrlController.text = _settings.pigWebUrl ?? '';
      _webLoggedIn = _settings.pigWebToken != null;
      _webDisplayName = _settings.pigWebUsername;
      _downloadWebMusic = _settings.downloadWebMusic;
      _onlyDownloadOnWifi = _settings.onlyDownloadOnWifi;
      if (_settings.pigWebUrl != null) {
        _webService.configure(_settings.pigWebUrl!);
      }
      if (_settings.pigWebToken != null && _settings.pigWebUsername != null) {
        _webService.setToken(_settings.pigWebToken!, _settings.pigWebUsername!);
      }
    });
  }

  Future<void> _loadStats() async {
    final db = DatabaseService();
    _songCount = await db.getSongCount();
    // Default music path — user can change this
    if (_musicPath.isEmpty) {
      _musicPath = '/storage/emulated/0/Music';
      // Check if running on desktop (for testing)
      if (!Platform.isAndroid && !Platform.isIOS) {
        final home = Platform.environment['HOME'] ?? '/home';
        _musicPath = '$home/Music';
      }
    }
    setState(() {});
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      // We need real filesystem access, not just MediaStore.
      // On Android 11+, MANAGE_EXTERNAL_STORAGE is required for Directory.list()
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (status.isGranted) return true;

      // Fallback for older Android
      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }
      return storageStatus.isGranted;
    }

    // iOS
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  Future<void> _scan() async {
    if (_scanning) return;

    // Request permissions first
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      setState(() {
        _scanStatus =
            'Permission denied. Please grant storage/media access in Settings.';
      });
      // Offer to open app settings
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Storage permission required'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _scanning = true;
      _scanStatus = 'Scanning...';
      _scanProgress = 0;
      _scanTotal = 0;
    });

    final db = DatabaseService();
    final scanner = ScannerService(db);

    try {
      final result = await scanner.scanDirectory(
        _musicPath,
        onProgress: (status, current, total) {
          setState(() {
            _scanStatus = status;
            _scanProgress = current;
            _scanTotal = total;
          });
        },
      );

      setState(() {
        _scanStatus = result.toString();
        _scanning = false;
      });
      _loadStats();
    } catch (e) {
      setState(() {
        _scanStatus = 'Error: $e';
        _scanning = false;
      });
    }
  }

  Future<void> _prune() async {
    setState(() => _scanStatus = 'Pruning deleted files...');
    final db = DatabaseService();
    final scanner = ScannerService(db);
    final pruned = await scanner.pruneDeletedFiles();
    setState(() => _scanStatus = 'Pruned $pruned songs with missing files.');
    _loadStats();
  }

  /// Re-read ID3 tags for all songs already in the database.
  Future<void> _rescanTags() async {
    setState(() {
      _scanning = true;
      _scanStatus = 'Re-reading tags...';
      _scanProgress = 0;
      _scanTotal = 0;
    });

    final db = DatabaseService();
    final allSongs = await db.getAllSongs();
    int updated = 0;

    for (int i = 0; i < allSongs.length; i++) {
      final song = allSongs[i];
      setState(() {
        _scanStatus = song.filePath.split('/').last;
        _scanProgress = i + 1;
        _scanTotal = allSongs.length;
      });

      try {
        final file = File(song.filePath);
        if (!await file.exists()) continue;

        final metadata = readMetadata(file, getImage: false);

        String? title = metadata.title;
        String? artist = metadata.artist;
        String? album = metadata.album;
        String? genre = metadata.genres.isNotEmpty
            ? metadata.genres.first
            : null;
        int? year = metadata.year?.year;
        int? durationMs = metadata.duration?.inMilliseconds;

        // Only update if we got something new
        bool changed = false;
        if (title != null && title.isNotEmpty && title != song.title)
          changed = true;
        if (artist != null && artist.isNotEmpty && artist != song.artist)
          changed = true;
        if (album != null && album.isNotEmpty && album != song.album)
          changed = true;
        if (genre != null && genre.isNotEmpty && genre != song.genre)
          changed = true;
        if (year != null && year != song.year) changed = true;
        if (durationMs != null && durationMs != song.durationMs) changed = true;

        if (changed) {
          final updatedSong = song.copyWith(
            title: (title != null && title.isNotEmpty) ? title : song.title,
            artist: (artist != null && artist.isNotEmpty)
                ? artist
                : song.artist,
            album: (album != null && album.isNotEmpty) ? album : song.album,
            genre: (genre != null && genre.isNotEmpty) ? genre : song.genre,
            year: year ?? song.year,
            durationMs: durationMs ?? song.durationMs,
          );
          await db.updateSong(updatedSong);
          updated++;
        }
      } catch (_) {
        // Skip files that can't be read
      }
    }

    setState(() {
      _scanStatus = 'Tags updated for $updated of ${allSongs.length} songs.';
      _scanning = false;
    });
  }

  /// Delete all playlists and re-import from .m3u files.
  Future<void> _reimportPlaylists() async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission) return;

    setState(() {
      _scanning = true;
      _scanStatus = 'Deleting existing playlists...';
    });

    final db = DatabaseService();

    // Delete all existing playlists
    final existing = await db.getAllPlaylists();
    for (final pl in existing) {
      if (pl.id != null) await db.deletePlaylist(pl.id!);
    }

    setState(() => _scanStatus = 'Scanning for .m3u files...');

    // Re-scan just for playlists
    final scanner = ScannerService(db);
    final result = await scanner.scanDirectory(
      _musicPath,
      onProgress: (status, current, total) {
        setState(() {
          _scanStatus = status;
          _scanProgress = current;
          _scanTotal = total;
        });
      },
    );

    setState(() {
      _scanStatus =
          'Playlists re-imported: ${result.playlistsImported} of ${result.totalPlaylists}';
      _scanning = false;
    });
  }

  /// Login to PIG Web.
  Future<void> _webLogin() async {
    final url = _webUrlController.text.trim();
    final username = _webUsernameController.text.trim();
    final password = _webPasswordController.text.trim();

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _webLoginStatus = 'URL, username, and password required.');
      return;
    }

    setState(() => _webLoginStatus = 'Logging in...');

    try {
      _webService.configure(url);
      final result = await _webService.login(username, password, 'PIG Mobile');
      final token = result['token'] as String;
      final displayName = result['displayName'] as String? ?? username;

      await _settings.setPigWebUrl(url);
      await _settings.setPigWebToken(token);
      await _settings.setPigWebUsername(displayName);

      setState(() {
        _webLoggedIn = true;
        _webDisplayName = displayName;
        _webLoginStatus = 'Connected!';
        _webPasswordController.clear();
      });
    } catch (e) {
      setState(() {
        _webLoginStatus = 'Login failed: $e';
        _webLoggedIn = false;
      });
    }
  }

  /// Logout from PIG Web.
  Future<void> _webLogout() async {
    _webService.logout();
    await _settings.setPigWebToken(null);
    await _settings.setPigWebUsername(null);
    setState(() {
      _webLoggedIn = false;
      _webDisplayName = null;
      _webLoginStatus = '';
    });
  }

  /// Show what the app can see at the current path.
  Future<void> _diagnose() async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      setState(() => _scanStatus = 'DIAG: No permission granted.');
      return;
    }

    final dir = Directory(_musicPath);
    final exists = await dir.exists();
    if (!exists) {
      setState(() => _scanStatus = 'DIAG: Path does not exist: $_musicPath');
      return;
    }

    final items = <String>[];
    int fileCount = 0;
    int dirCount = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split('/').last;
        if (entity is Directory) {
          dirCount++;
          items.add('📁 $name/');
        } else if (entity is File) {
          fileCount++;
          items.add('📄 $name');
        }
        if (items.length >= 30) {
          items.add('... and more');
          break;
        }
      }
    } on PathAccessException catch (e) {
      setState(
        () => _scanStatus = 'DIAG: Permission denied listing $_musicPath: $e',
      );
      return;
    } catch (e) {
      setState(() => _scanStatus = 'DIAG: Error listing: $e');
      return;
    }

    setState(() {
      _scanStatus =
          'DIAG: $dirCount dirs, $fileCount files at $_musicPath\n${items.join('\n')}';
    });
  }

  /// Simple folder browser dialog.
  Future<void> _browseFolders(String startPath) async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission || !mounted) return;

    String currentPath = startPath;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: PigTheme.darkNavy,
              title: Text(
                currentPath.split('/').last.isEmpty
                    ? '/'
                    : currentPath.split('/').last,
                style: const TextStyle(color: PigTheme.hotPink, fontSize: 14),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: FutureBuilder<List<FileSystemEntity>>(
                  future: _listDir(currentPath),
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    final entities = snapshot.data ?? [];
                    final dirs = entities.whereType<Directory>().toList()
                      ..sort((a, b) => a.path.compareTo(b.path));

                    return Column(
                      children: [
                        // Current path display
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: PigTheme.navy,
                          width: double.infinity,
                          child: Text(
                            currentPath,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView(
                            children: [
                              // Go up
                              if (currentPath != '/')
                                ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.arrow_upward,
                                    color: PigTheme.goldenrod,
                                    size: 20,
                                  ),
                                  title: const Text(
                                    '..',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  onTap: () {
                                    final parent = Directory(
                                      currentPath,
                                    ).parent.path;
                                    setDialogState(() => currentPath = parent);
                                  },
                                ),
                              // Subdirectories
                              ...dirs.map((d) {
                                final name = d.path.split('/').last;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.folder,
                                    color: PigTheme.goldenrod,
                                    size: 20,
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onTap: () {
                                    setDialogState(() => currentPath = d.path);
                                  },
                                );
                              }),
                              if (dirs.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'No subdirectories',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _musicPath = currentPath);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PigTheme.maroon,
                    foregroundColor: PigTheme.hotPink,
                  ),
                  child: const Text('Select This Folder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<FileSystemEntity>> _listDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final entities = <FileSystemEntity>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        entities.add(entity);
      }
    } catch (_) {}
    return entities;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PIG logo + title
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/pig.png',
                  width: 80,
                  height: 80,
                  errorBuilder: (_, e, s) => const Icon(
                    Icons.music_note,
                    size: 80,
                    color: PigTheme.hotPink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'PIG Mobile',
                  style: TextStyle(
                    color: PigTheme.hotPink,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Playlist Intelligent Generator',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'v$appVersion',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Library',
                    style: TextStyle(
                      color: PigTheme.goldenrod,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _statRow('Songs in database', '$_songCount'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Music folder
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Music Folder',
                    style: TextStyle(
                      color: PigTheme.goldenrod,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: _musicPath),
                    decoration: InputDecoration(
                      hintText: 'Path to music folder',
                      prefixIcon: const Icon(
                        Icons.folder,
                        color: PigTheme.goldenrod,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.folder_open,
                          color: PigTheme.hotPink,
                        ),
                        tooltip: 'Browse folders',
                        onPressed: () => _browseFolders('/storage/emulated/0'),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onChanged: (val) => _musicPath = val,
                  ),
                  const SizedBox(height: 6),
                  // Quick diagnostic
                  TextButton.icon(
                    onPressed: _diagnose,
                    icon: const Icon(
                      Icons.bug_report,
                      size: 16,
                      color: Colors.grey,
                    ),
                    label: const Text(
                      'Diagnose path',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _scanning ? null : _scan,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_scanning ? 'Scanning...' : 'Scan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PigTheme.maroon,
                          foregroundColor: PigTheme.hotPink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _scanning ? null : _prune,
                        icon: const Icon(Icons.cleaning_services),
                        label: const Text('Prune'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PigTheme.darkNavy,
                          foregroundColor: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _scanning ? null : _rescanTags,
                        icon: const Icon(Icons.tag),
                        label: const Text('Rescan Tags'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PigTheme.darkNavy,
                          foregroundColor: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _scanning ? null : _reimportPlaylists,
                        icon: const Icon(Icons.queue_music),
                        label: const Text('Re-import Playlists'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PigTheme.darkNavy,
                          foregroundColor: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  if (_scanStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    if (_scanTotal > 0)
                      LinearProgressIndicator(
                        value: _scanProgress / _scanTotal,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: const AlwaysStoppedAnimation(
                          PigTheme.hotPink,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _scanTotal > 0
                          ? '$_scanProgress / $_scanTotal: $_scanStatus'
                          : _scanStatus,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 15,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // PIG Web
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PIG Web',
                    style: TextStyle(
                      color: PigTheme.goldenrod,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Connect to your PIG Web server to stream or download music.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  // URL
                  TextField(
                    controller: _webUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://piggy.dirtsailor.org',
                      labelText: 'PIG Web URL',
                      prefixIcon: Icon(Icons.link, color: PigTheme.goldenrod),
                      isDense: true,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onChanged: (val) async {
                      await _settings.setPigWebUrl(val.trim());
                      if (val.trim().isNotEmpty) {
                        _webService.configure(val.trim());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Login section
                  if (!_webLoggedIn) ...[
                    TextField(
                      controller: _webUsernameController,
                      decoration: const InputDecoration(
                        hintText: 'Username',
                        labelText: 'Username',
                        prefixIcon: Icon(
                          Icons.person,
                          color: PigTheme.goldenrod,
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _webPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        hintText: 'Password',
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock, color: PigTheme.goldenrod),
                        isDense: true,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _webLogin,
                      icon: const Icon(Icons.login),
                      label: const Text('Login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PigTheme.maroon,
                        foregroundColor: PigTheme.hotPink,
                      ),
                    ),
                  ] else ...[
                    // Logged in state
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: PigTheme.lawnGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Logged in as $_webDisplayName',
                          style: const TextStyle(
                            color: PigTheme.lawnGreen,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _webLogout,
                          child: const Text(
                            'Logout',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_webLoginStatus.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _webLoginStatus,
                      style: TextStyle(
                        color: _webLoggedIn ? PigTheme.lawnGreen : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Download toggles
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Download Web Music',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Save streamed songs to device for offline play',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    value: _downloadWebMusic,
                    activeThumbColor: PigTheme.hotPink,
                    onChanged: (val) async {
                      setState(() => _downloadWebMusic = val);
                      await _settings.setDownloadWebMusic(val);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Only Download on WiFi',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Prevent downloads over mobile data',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    value: _onlyDownloadOnWifi,
                    activeThumbColor: PigTheme.hotPink,
                    onChanged: (val) async {
                      setState(() => _onlyDownloadOnWifi = val);
                      await _settings.setOnlyDownloadOnWifi(val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About',
                    style: TextStyle(
                      color: PigTheme.goldenrod,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'PIG Mobile is the Android/iOS companion to PIGv4. '
                    'Songs are read from your device\'s music folder instead of '
                    'being embedded in a database. Create Gen Playlists, browse '
                    'by artist/genre/folder, and enjoy your music. 🐷🎶',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: PigTheme.cyan, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(color: PigTheme.hotPink, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
