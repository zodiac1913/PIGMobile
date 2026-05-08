/// Gen Playlist — mirrors PIGv4's List table.
class Playlist {
  final int? id;
  final String title;
  final int minimum;
  final DateTime created;

  Playlist({
    this.id,
    required this.title,
    this.minimum = 0,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'minimum': minimum,
      'created': created.toIso8601String(),
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as int?,
      title: map['title'] as String,
      minimum: map['minimum'] as int? ?? 0,
      created: DateTime.tryParse(map['created'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Filter assignment — mirrors PIGv4's ListFilter table.
/// HasTitle = this specific song is in the playlist.
/// HasArtist = ALL songs by this artist are in the playlist.
class SongFilter {
  final int? id;
  final int playlistId;
  final int songId;
  final bool hasTitle;
  final bool hasArtist;

  SongFilter({
    this.id,
    required this.playlistId,
    required this.songId,
    this.hasTitle = false,
    this.hasArtist = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'playlistId': playlistId,
      'songId': songId,
      'hasTitle': hasTitle ? 1 : 0,
      'hasArtist': hasArtist ? 1 : 0,
    };
  }

  factory SongFilter.fromMap(Map<String, dynamic> map) {
    return SongFilter(
      id: map['id'] as int?,
      playlistId: map['playlistId'] as int,
      songId: map['songId'] as int,
      hasTitle: (map['hasTitle'] as int?) == 1,
      hasArtist: (map['hasArtist'] as int?) == 1,
    );
  }
}
