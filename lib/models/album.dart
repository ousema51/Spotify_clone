import 'song.dart';

class Album {
  final String id;
  final String title;
  final String? artist;
  final String? coverUrl;
  final int? songCount;
  final List<Song>? songs;

  const Album({
    required this.id,
    required this.title,
    this.artist,
    this.coverUrl,
    this.songCount,
    this.songs,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    List<Song>? songs;
    final rawSongs = json['songs'] ?? json['tracks'];
    if (rawSongs is List) {
      songs = rawSongs
          .map((s) => Song.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    String? artist;
    final rawArtist = json['artists'] ?? json['artist'] ?? json['primary_artists'];
    if (rawArtist is String) {
      artist = rawArtist;
    } else if (rawArtist is List && rawArtist.isNotEmpty) {
      final first = rawArtist.first;
      artist = (first is Map ? first['name'] : first)?.toString();
    } else if (rawArtist is Map) {
      final primary = rawArtist['primary'];
      if (primary is List && primary.isNotEmpty) {
        final first = primary.first;
        artist = (first is Map ? first['name'] : first)?.toString();
      } else {
        artist = rawArtist['name']?.toString();
      }
    }

    String? coverUrl;
    final rawImage = json['image'] ?? json['cover_url'] ?? json['coverUrl'];
    if (rawImage is String) {
      coverUrl = rawImage;
    } else if (rawImage is List && rawImage.isNotEmpty) {
      final best = rawImage.lastWhere(
        (img) => img is Map && img['quality'] == '500x500',
        orElse: () => rawImage.last,
      );
      coverUrl = (best is Map
          ? (best['url'] ?? best['link'])
          : best)?.toString();
    }

    return Album(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['name'] ?? json['title'] ?? 'Unknown').toString(),
      artist: artist,
      coverUrl: coverUrl,
      songCount: _parseSongCount(json['songCount'] ?? json['song_count']) ?? songs?.length,
      songs: songs,
    );
  }

  static int? _parseSongCount(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}
