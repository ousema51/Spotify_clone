import 'song.dart';
import 'album.dart';

class Artist {
  final String id;
  final String name;
  final String? imageUrl;
  final String? bio;
  final int? followerCount;
  final List<Song>? topSongs;
  final List<Album>? topAlbums;

  const Artist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.bio,
    this.followerCount,
    this.topSongs,
    this.topAlbums,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    List<Song>? topSongs;
    final rawSongs = json['top_songs'] ?? json['topSongs'] ?? json['songs'];
    if (rawSongs is List) {
      topSongs = rawSongs
          .map((s) => Song.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    List<Album>? topAlbums;
    final rawAlbums =
        json['top_albums'] ?? json['topAlbums'] ?? json['albums'];
    if (rawAlbums is List) {
      topAlbums = rawAlbums
          .map((a) => Album.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    String? imageUrl;
    final rawImage = json['image'] ?? json['image_url'] ?? json['imageUrl'];
    if (rawImage is String) {
      imageUrl = rawImage;
    } else if (rawImage is List && rawImage.isNotEmpty) {
      final best = rawImage.lastWhere(
        (img) => img is Map && img['quality'] == '500x500',
        orElse: () => rawImage.last,
      );
      imageUrl = (best is Map
          ? (best['url'] ?? best['link'])
          : best)?.toString();
    }

    int? followerCount;
    final rawFollowers = json['follower_count'] ??
        json['followerCount'] ??
        json['fans'];
    if (rawFollowers is int) {
      followerCount = rawFollowers;
    } else if (rawFollowers is String) {
      followerCount = int.tryParse(rawFollowers);
    }

    return Artist(
      id: (json['id'] ?? json['_id'] ?? json['artistid'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Unknown Artist').toString(),
      imageUrl: imageUrl,
      bio: json['bio']?.toString() ?? json['description']?.toString(),
      followerCount: followerCount,
      topSongs: topSongs,
      topAlbums: topAlbums,
    );
  }
}
