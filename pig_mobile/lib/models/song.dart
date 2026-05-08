/// Song model — mirrors PIGv4's Piece table but reads from device files.
class Song {
  final int? id;
  final String filePath;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? year;
  final int? durationMs;
  final int? bpm;
  final String? sourceFolder;
  final bool isNew;

  Song({
    this.id,
    required this.filePath,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.year,
    this.durationMs,
    this.bpm,
    this.sourceFolder,
    this.isNew = true,
  });

  String get displayTitle => title ?? filePath.split('/').last;
  String get displayArtist => artist ?? 'Unknown Artist';
  String get displayAlbum => album ?? '';

  String get durationFormatted {
    if (durationMs == null) return '0:00';
    final totalSec = durationMs! ~/ 1000;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'year': year,
      'durationMs': durationMs,
      'bpm': bpm,
      'sourceFolder': sourceFolder,
      'isNew': isNew ? 1 : 0,
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as int?,
      filePath: map['filePath'] as String,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      genre: map['genre'] as String?,
      year: map['year'] as int?,
      durationMs: map['durationMs'] as int?,
      bpm: map['bpm'] as int?,
      sourceFolder: map['sourceFolder'] as String?,
      isNew: (map['isNew'] as int?) == 1,
    );
  }

  Song copyWith({
    int? id,
    String? filePath,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? year,
    int? durationMs,
    int? bpm,
    String? sourceFolder,
    bool? isNew,
  }) {
    return Song(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      bpm: bpm ?? this.bpm,
      sourceFolder: sourceFolder ?? this.sourceFolder,
      isNew: isNew ?? this.isNew,
    );
  }
}
