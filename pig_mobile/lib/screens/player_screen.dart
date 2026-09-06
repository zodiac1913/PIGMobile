import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../services/audio_service.dart';
import '../services/browse_state.dart';
import '../theme.dart';

/// Player tab — transport, seek, volume, upcoming songs, song info modal.
class PlayerScreen extends StatefulWidget {
  final bool asTab;
  const PlayerScreen({super.key, this.asTab = false});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    final audio = context.read<AudioService>();
    _volume = audio.volume;
  }

  void _toggleKeepScreenOn() {
    final audio = context.read<AudioService>();
    audio.setKeepScreenOn(!audio.keepScreenOn);
  }

  /// Center Play/Pause button — operates on whatever is currently loaded
  /// (whichever of the two "play random" buttons was last pressed).
  /// If nothing is loaded, it defaults to playing the selection queue (if any),
  /// otherwise all songs random.
  Future<void> _handlePlay() async {
    final audio = context.read<AudioService>();

    // Already have something loaded — just toggle pause/play
    if (audio.currentSong != null || audio.playlist.isNotEmpty) {
      audio.toggle();
      return;
    }

    // Nothing loaded — sensible default: selection first, then all random
    final browseState = context.read<BrowseState>();
    if (browseState.hasQueue) {
      await audio.playSelectionRandom(
        browseState.queue,
        webService: browseState.isWeb ? browseState.webService : null,
      );
      return;
    }

    await audio.playAllRandom();

    // If still nothing (empty library), tell the user
    if (!mounted) return;
    if (audio.playlist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No music available. Scan your music folder in Settings, or select music from the Browse tab.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  /// Play All Random button — explicitly play all songs shuffled.
  Future<void> _handlePlayAllRandom() async {
    final audio = context.read<AudioService>();
    await audio.playAllRandom();
    if (!mounted) return;
    if (audio.playlist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No music available. Scan your music folder in Settings.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Play Selection Random button — explicitly play the selection queue shuffled.
  /// Re-resolves the queue fresh from the current selections so it always
  /// matches the checkboxes (never plays a stale queue).
  Future<void> _handlePlaySelectionRandom() async {
    final audio = context.read<AudioService>();
    final browseState = context.read<BrowseState>();

    // Nothing selected at all
    if (!browseState.hasSelections && !browseState.hasQueue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No selection queued. Choose music in the Browse tab first.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Resolve songs fresh from the current selections (local) — authoritative.
    final songs = await browseState.resolveSelectionSongs();
    if (songs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your selection resolved to no songs.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await audio.playSelectionRandom(
      songs,
      webService: browseState.isWeb ? browseState.webService : null,
    );
  }

  void _showSongInfoModal(BuildContext context, AudioService audio) {
    final song = audio.currentSong;
    if (song == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Don't dismiss when tapping the modal itself
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: PigTheme.darkNavy,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: PigTheme.goldenrod, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(
                          Icons.close,
                          color: Colors.grey,
                          size: 22,
                        ),
                      ),
                    ),
                    // Album art
                    if (audio.currentAlbumArt != null &&
                        audio.currentAlbumArt!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          Uint8List.fromList(audio.currentAlbumArt!),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, s) => const SizedBox.shrink(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Song info — only show fields with data
                    Text(
                      song.displayTitle,
                      style: const TextStyle(
                        color: PigTheme.hotPink,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (song.artist != null && song.artist!.isNotEmpty)
                      _infoLine('Artist', song.artist!),
                    if (song.album != null && song.album!.isNotEmpty)
                      _infoLine('Album', song.album!),
                    if (song.genre != null && song.genre!.isNotEmpty)
                      _infoLine('Genre', song.genre!),
                    if (song.year != null) _infoLine('Year', '${song.year}'),
                    if (song.sourceFolder != null &&
                        song.sourceFolder!.isNotEmpty)
                      _infoLine('Folder', song.sourceFolder!),
                    if (audio.currentPlaylists.isNotEmpty)
                      _infoLine(
                        'Gen Playlists',
                        audio.currentPlaylists.join(', '),
                      ),
                    if (song.durationMs != null)
                      _infoLine('Duration', song.durationFormatted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: PigTheme.cyan, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: PigTheme.hotPink, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    final content = Consumer<AudioService>(
      builder: (context, audio, _) {
        final song = audio.currentSong;

        if (isLandscape) {
          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.10,
                  child: Image.asset(
                    'assets/PIGTranBG.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, e, s) => const SizedBox.shrink(),
                  ),
                ),
              ),
              SafeArea(
                child: Row(
                  children: [
                    // Left: Controls (2 Rows)
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TransportControls(
                            audio: audio,
                            onPlay: _handlePlay,
                            isVertical: false,
                          ),
                          const SizedBox(height: 16),
                          _ControlsRow(
                            audio: audio,
                            keepScreenOn: audio.keepScreenOn,
                            onToggleKeepScreenOn: _toggleKeepScreenOn,
                            onPlayAllRandom: _handlePlayAllRandom,
                            onPlaySelectionRandom: _handlePlaySelectionRandom,
                            isVertical: false,
                          ),
                        ],
                      ),
                    ),
                    // Center: Art + Info
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: song != null
                                ? () => _showSongInfoModal(context, audio)
                                : null,
                            child: _AlbumArt(
                              albumArt: audio.currentAlbumArt,
                              size: 160,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (song != null)
                            Column(
                              children: [
                                Text(
                                  song.displayTitle,
                                  style: const TextStyle(
                                    color: PigTheme.hotPink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  song.displayArtist,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          _SeekBar(audio: audio),
                        ],
                      ),
                    ),
                    // Right: Upcoming List
                    Expanded(
                      flex: 3,
                      child: _UpcomingList(audio: audio, isVertical: true),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Stack(
          children: [
            // Background
            Positioned.fill(
              child: Opacity(
                opacity: 0.10,
                child: Image.asset(
                  'assets/PIGTranBG.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, e, s) => const SizedBox.shrink(),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Main player area (scrollable)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          // Album art — tap for info modal
                          GestureDetector(
                            onTap: song != null
                                ? () => _showSongInfoModal(context, audio)
                                : null,
                            child: _AlbumArt(albumArt: audio.currentAlbumArt),
                          ),
                          const SizedBox(height: 12),
                          // Song title + artist (tap for modal)
                          if (song != null)
                            GestureDetector(
                              onTap: () => _showSongInfoModal(context, audio),
                              child: Column(
                                children: [
                                  Text(
                                    song.displayTitle,
                                    style: const TextStyle(
                                      color: PigTheme.hotPink,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (song.artist != null &&
                                      song.artist!.isNotEmpty)
                                    Text(
                                      song.artist!,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                ],
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                'Tap Play to start',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          // Seek bar
                          _SeekBar(audio: audio),
                          const SizedBox(height: 8),
                          // Transport
                          _TransportControls(audio: audio, onPlay: _handlePlay),
                          const SizedBox(height: 10),
                          // Shuffle / Repeat / Screen / Play All / Play Selection
                          _ControlsRow(
                            audio: audio,
                            keepScreenOn: audio.keepScreenOn,
                            onToggleKeepScreenOn: _toggleKeepScreenOn,
                            onPlayAllRandom: _handlePlayAllRandom,
                            onPlaySelectionRandom: _handlePlaySelectionRandom,
                          ),
                          const SizedBox(height: 10),
                          // Volume
                          _VolumeSlider(
                            volume: _volume,
                            onChanged: (val) {
                              setState(() => _volume = val);
                              audio.setVolume(val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Upcoming songs at bottom
                  _UpcomingList(audio: audio),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (widget.asTab) return content;
    return Scaffold(
      backgroundColor: PigTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Now Playing'),
        backgroundColor: PigTheme.navy,
      ),
      body: content,
    );
  }
}

/// Album art widget.
class _AlbumArt extends StatelessWidget {
  final List<int>? albumArt;
  final double size;
  const _AlbumArt({this.albumArt, this.size = 240});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PigTheme.maroon.withAlpha(80),
        borderRadius: BorderRadius.circular(size * 0.08),
        border: Border.all(color: PigTheme.goldenrod, width: 2.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: albumArt != null && albumArt!.isNotEmpty
            ? Image.memory(
                Uint8List.fromList(albumArt!),
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Image.asset(
      'assets/pigicon.png',
      fit: BoxFit.contain,
      errorBuilder: (_, e, s) =>
          const Icon(Icons.music_note, size: 60, color: PigTheme.hotPink),
    );
  }
}

class _UpcomingList extends StatelessWidget {
  final AudioService audio;
  final bool isVertical;
  const _UpcomingList({required this.audio, this.isVertical = false});

  @override
  Widget build(BuildContext context) {
    if (audio.playlist.isEmpty || audio.currentIndex < 0) {
      return const SizedBox.shrink();
    }

    // Get next 3 songs after current
    final upcoming = <int>[];
    for (
      int i = audio.currentIndex + 1;
      i < audio.playlist.length && upcoming.length < 3;
      i++
    ) {
      upcoming.add(i);
    }

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: PigTheme.navy,
        border: isVertical
            ? const Border(left: BorderSide(color: PigTheme.maroon, width: 1))
            : const Border(top: BorderSide(color: PigTheme.maroon, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: isVertical ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'Up Next',
              style: TextStyle(
                color: PigTheme.hotPink.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...upcoming.map((idx) {
            final song = audio.playlist[idx];
            return Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.displayArtist,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.grey,
                    onPressed: () => audio.removeFromPlaylist(idx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final AudioService audio;
  const _SeekBar({required this.audio});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final dur = audio.duration;
        final maxVal = dur.inMilliseconds.toDouble();
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: maxVal > 0
                    ? pos.inMilliseconds.toDouble().clamp(0, maxVal)
                    : 0,
                max: maxVal > 0 ? maxVal : 1,
                onChanged: (val) =>
                    audio.seek(Duration(milliseconds: val.toInt())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(pos),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  Text(
                    _fmt(dur),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _TransportControls extends StatelessWidget {
  final AudioService audio;
  final VoidCallback onPlay;
  final bool isVertical;
  const _TransportControls({
    required this.audio,
    required this.onPlay,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: PigTheme.goldenrod, width: 2.5),
        borderRadius: BorderRadius.circular(isVertical ? 20 : 60),
      ),
      padding: const EdgeInsets.all(8),
      child: StreamBuilder<PlayerState>(
        stream: audio.playerStateStream,
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing ?? false;
          final buttons = [
            _btn(
              Icons.skip_previous_rounded,
              52, // Same as portrait
              Colors.white,
              () => audio.prev(),
            ),
            _btn(
              playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              92, // Same as portrait
              PigTheme.hotPink,
              onPlay,
            ),
            _btn(
              Icons.stop_circle_rounded,
              60, // Same as portrait
              Colors.white,
              () => audio.stop(),
            ),
            _btn(
              Icons.skip_next_rounded,
              52, // Same as portrait
              Colors.white,
              () => audio.next(),
            ),
          ];

          return isVertical
              ? Column(mainAxisSize: MainAxisSize.min, children: buttons)
              : Row(mainAxisSize: MainAxisSize.min, children: buttons);
        },
      ),
    );
  }

  Widget _btn(IconData icon, double size, Color color, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: size),
      color: color,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  final AudioService audio;
  final bool keepScreenOn;
  final VoidCallback onToggleKeepScreenOn;
  final VoidCallback onPlayAllRandom;
  final VoidCallback onPlaySelectionRandom;
  final bool isVertical;
  const _ControlsRow({
    required this.audio,
    required this.keepScreenOn,
    required this.onToggleKeepScreenOn,
    required this.onPlayAllRandom,
    required this.onPlaySelectionRandom,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    // Spacing reduced ~10% (16 -> 14) to fit all 5 buttons on one line.
    final spacing = isVertical
        ? const SizedBox(height: 11)
        : const SizedBox(width: 14);

    final buttons = <Widget>[
      _tog(
        Icons.shuffle_rounded,
        audio.shuffle,
        PigTheme.hotPink,
        () => audio.toggleShuffle(),
      ),
      spacing,
      _tog(
        audio.repeatMode == PigRepeatMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        audio.repeatMode != PigRepeatMode.off,
        audio.repeatMode == PigRepeatMode.one
            ? PigTheme.goldenrod
            : PigTheme.hotPink,
        () => audio.toggleRepeat(),
      ),
      spacing,
      _tog(
        Icons.light_mode_rounded,
        keepScreenOn,
        PigTheme.goldenrod,
        onToggleKeepScreenOn,
      ),
      // Play All Random — hollow pink triangle with white shuffle overlay
      spacing,
      _playAllRandomButton(),
      // Play Selection Random — hollow red triangle with white "Q" overlay
      spacing,
      _playSelectionRandomButton(),
    ];

    return isVertical
        ? Column(mainAxisSize: MainAxisSize.min, children: buttons)
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons);
  }

  /// Play All Random — hot pink hollow triangle with a white shuffle overlay.
  /// Plays ALL songs in random order. Soft white fill when active.
  Widget _playAllRandomButton() {
    final active = audio.playMode == PigPlayMode.all;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: PigTheme.hotPink, width: 2),
        // Soft transparent white when active, else faint pink tint.
        color: active
            ? Colors.white.withAlpha(46)
            : PigTheme.hotPink.withAlpha(30),
      ),
      child: IconButton(
        tooltip: 'Play all songs (random)',
        icon: Stack(
          alignment: Alignment.center,
          children: [
            // Icon +5% (24 -> 25)
            const Icon(
              Icons.play_arrow_outlined,
              size: 25,
              color: PigTheme.hotPink,
            ),
            // Overlay +5% (11 -> 12)
            const Icon(Icons.shuffle_rounded, size: 12, color: Colors.white),
          ],
        ),
        onPressed: onPlayAllRandom,
        // Padding -10% (8 -> 7)
        padding: const EdgeInsets.all(7),
        constraints: const BoxConstraints(),
      ),
    );
  }

  /// Play Selection Random — hot pink hollow circle, red play triangle, white "Q".
  /// Plays the current selection queue in random order. Soft white fill when active.
  Widget _playSelectionRandomButton() {
    final active = audio.playMode == PigPlayMode.selection;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Outer circle matches the others (hot pink).
        border: Border.all(color: PigTheme.hotPink, width: 2),
        // Soft transparent white when active, else faint pink tint.
        color: active
            ? Colors.white.withAlpha(46)
            : PigTheme.hotPink.withAlpha(30),
      ),
      child: IconButton(
        tooltip: 'Play selection (random)',
        icon: Stack(
          alignment: Alignment.center,
          children: const [
            // Internal play symbol stays red. Icon +5% (24 -> 25)
            Icon(Icons.play_arrow_outlined, size: 25, color: Colors.red),
            // Q text +5% (13 -> 14)
            Text(
              'Q',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        onPressed: onPlaySelectionRandom,
        // Padding -10% (8 -> 7)
        padding: const EdgeInsets.all(7),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _tog(
    IconData icon,
    bool active,
    Color activeColor,
    VoidCallback onPressed,
  ) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? activeColor : Colors.grey.shade700,
          width: 2,
        ),
        color: active ? activeColor.withAlpha(30) : Colors.transparent,
      ),
      child: IconButton(
        // Icon +5% (20 -> 21)
        icon: Icon(icon, size: 21),
        color: active ? activeColor : Colors.grey,
        onPressed: onPressed,
        // Padding -10% (8 -> 7)
        padding: const EdgeInsets.all(7),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final double volume;
  final ValueChanged<double> onChanged;
  const _VolumeSlider({required this.volume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          volume == 0 ? Icons.volume_off : Icons.volume_down,
          color: Colors.grey,
          size: 18,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: PigTheme.goldenrod,
              thumbColor: PigTheme.goldenrod,
              inactiveTrackColor: Colors.grey.shade800,
            ),
            child: Slider(value: volume, min: 0, max: 1, onChanged: onChanged),
          ),
        ),
        const Icon(Icons.volume_up, color: Colors.grey, size: 18),
      ],
    );
  }
}
