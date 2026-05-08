import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../services/audio_service.dart';
import '../theme.dart';

/// Bottom mini player bar — mirrors PIGv4's miniPlayer in the navbar.
class MiniPlayer extends StatelessWidget {
  final VoidCallback? onTap;

  const MiniPlayer({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audio, _) {
        if (audio.currentSong == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              color: PigTheme.navy,
              border: Border(top: BorderSide(color: PigTheme.maroon, width: 2)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // Song info
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audio.currentSong!.displayTitle,
                        style: const TextStyle(
                            color: PigTheme.hotPink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        audio.currentSong!.displayArtist,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Transport controls
                _TransportControls(audio: audio),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TransportControls extends StatelessWidget {
  final AudioService audio;

  const _TransportControls({required this.audio});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: PigTheme.goldenrod, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: StreamBuilder<PlayerState>(
        stream: audio.playerStateStream,
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing ?? false;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniBtn(Icons.skip_previous, () => audio.prev()),
              _miniBtn(
                playing ? Icons.pause : Icons.play_arrow,
                () => audio.toggle(),
              ),
              _miniBtn(Icons.stop, () => audio.stop()),
              _miniBtn(Icons.skip_next, () => audio.next()),
            ],
          );
        },
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        color: Colors.white,
      ),
    );
  }
}
