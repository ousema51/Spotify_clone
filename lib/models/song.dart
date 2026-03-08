class Song {
  final String id;
  final String title;
  final String? artist;
  final List<String>? artists;
  final String? albumName;
  final String? coverUrl;
  final int? duration;
  final String? streamUrl;
  final String? albumId;

  const Song({
    required this.id,
    required this.title,
    this.artist,
    this.artists,
    this.albumName,
    this.coverUrl,
    this.duration,
    this.streamUrl,
    this.albumId,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['name'] ?? json['title'] ?? 'Unknown').toString(),
      artist: _parsePrimaryArtist(json['artists'] ?? json['artist']),
      artists: _parseAllArtists(json['artists'] ?? json['artist']),
      albumName: _parseAlbumName(json['album']),
      coverUrl: _getBestImage(json['image'] ?? json['cover_url'] ?? json['coverUrl']),
      duration: _parseDuration(json['duration']),
      streamUrl: _getBestStreamUrl(json['download_url'] ?? json['downloadUrl'] ?? json['stream_url']),
      albumId: _parseAlbumId(json['album']),
    );
  }

  static String? _parsePrimaryArtist(dynamic artists) {
    if (artists == null) return null;
    if (artists is String) return artists;
    if (artists is Map) {
      final primary = artists['primary'];
      if (primary is List && primary.isNotEmpty) {
        return (primary.first['name'] ?? '').toString();
      }
      if (artists['name'] != null) return artists['name'].toString();
    }
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) return (first['name'] ?? '').toString();
      return first.toString();
    }
    return null;
  }

  static List<String>? _parseAllArtists(dynamic artists) {
    if (artists == null) return null;
    if (artists is String) return [artists];
    if (artists is Map) {
      final all = artists['all'] ?? artists['primary'];
      if (all is List) {
        return all
            .map((a) => (a is Map ? (a['name'] ?? '') : a).toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (artists['name'] != null) return [artists['name'].toString()];
    }
    if (artists is List) {
      return artists
          .map((a) => (a is Map ? (a['name'] ?? '') : a).toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return null;
  }

  static String? _parseAlbumName(dynamic album) {
    if (album == null) return null;
    if (album is String) return album;
    if (album is Map) return (album['name'] ?? album['title'])?.toString();
    return null;
  }

  static String? _parseAlbumId(dynamic album) {
    if (album == null) return null;
    if (album is Map) return (album['id'] ?? album['_id'])?.toString();
    return null;
  }

  static int? _parseDuration(dynamic duration) {
    if (duration == null) return null;
    if (duration is int) return duration;
    if (duration is String) return int.tryParse(duration);
    if (duration is double) return duration.toInt();
    return null;
  }

  static String? _getBestImage(dynamic images) {
    if (images == null) return null;
    if (images is String) return images;
    if (images is List && images.isNotEmpty) {
      final best = images.lastWhere(
        (img) => img is Map && img['quality'] == '500x500',
        orElse: () => images.last,
      );
      if (best is Map) return (best['url'] ?? best['link'])?.toString();
      if (best is String) return best;
    }
    if (images is Map) return (images['url'] ?? images['link'])?.toString();
    return null;
  }

  static String? _getBestStreamUrl(dynamic downloadUrls) {
    if (downloadUrls == null) return null;
    if (downloadUrls is String) return downloadUrls;
    if (downloadUrls is List && downloadUrls.isNotEmpty) {
      final best = downloadUrls.lastWhere(
        (url) => url is Map && url['quality'] == '320kbps',
        orElse: () => downloadUrls.last,
      );
      if (best is Map) return (best['url'] ?? best['link'])?.toString();
      if (best is String) return best;
    }
    if (downloadUrls is Map) {
      return (downloadUrls['url'] ?? downloadUrls['link'])?.toString();
    }
    return null;
  }

  Map<String, dynamic> toMetadata() {
    return {
      'id': id,
      'title': title,
      'artist': artist ?? '',
      'album': albumName ?? '',
      'cover_url': coverUrl ?? '',
      'duration': duration ?? 0,
    };
  }
}
