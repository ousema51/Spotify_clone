import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'api_service.dart';

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final ApiService _api = ApiService();

  // --- Search ---
  Future<List<Song>> searchSongs(String query) async {
    final result =
        await _api.get('/music/search?q=${Uri.encodeComponent(query)}&type=songs', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          data['songs'] ?? data['results'] ?? data ?? [];
      return items.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<Album>> searchAlbums(String query) async {
    final result = await _api
        .get('/music/search?q=${Uri.encodeComponent(query)}&type=albums', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          data['albums'] ?? data['results'] ?? data ?? [];
      return items
          .map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Artist>> searchArtists(String query) async {
    final result = await _api
        .get('/music/search?q=${Uri.encodeComponent(query)}&type=artists', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          data['artists'] ?? data['results'] ?? data ?? [];
      return items
          .map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // --- Individual fetch ---
  Future<Song?> getSong(String songId) async {
    final result = await _api.get('/music/song/$songId', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      return Song.fromJson(result['data'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<Album?> getAlbum(String albumId) async {
    final result = await _api.get('/music/album/$albumId', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      return Album.fromJson(result['data'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<Artist?> getArtist(String artistId) async {
    final result = await _api.get('/music/artist/$artistId', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      return Artist.fromJson(result['data'] as Map<String, dynamic>);
    }
    return null;
  }

  // --- Trending / Home ---
  Future<List<Song>> getTrending() async {
    final result = await _api.get('/music/trending', requiresAuth: false);
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          data is List ? data : (data['songs'] ?? data['trending'] ?? data['results'] ?? []);
      return items.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  // --- Library ---
  Future<Map<String, dynamic>> likeSong(
      String songId, Map<String, dynamic> metadata) async {
    return _api.post('/library/like/$songId', metadata);
  }

  Future<Map<String, dynamic>> unlikeSong(String songId) async {
    return _api.delete('/library/like/$songId');
  }

  Future<bool> checkLiked(String songId) async {
    final result = await _api.get('/library/liked/check/$songId');
    return result['data']?['liked'] == true;
  }

  Future<List<Song>> getLikedSongs() async {
    final result = await _api.get('/library/liked');
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          (data is Map ? data['songs'] : data) as List<dynamic>? ?? [];
      return items.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  // --- History / Suggestions ---
  Future<Map<String, dynamic>> trackListen(String songId,
      Map<String, dynamic> metadata, int listenedSeconds, int totalDuration) async {
    return _api.post('/listen/track', {
      'song_id': songId,
      'song_metadata': metadata,
      'listened_seconds': listenedSeconds,
      'total_duration': totalDuration,
    });
  }

  Future<List<Song>> getRecentHistory() async {
    final result = await _api.get('/history/recent');
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          (data is Map ? data['songs'] : data) as List<dynamic>? ?? [];
      return items.map((e) {
        final song = e['song'] ?? e;
        return Song.fromJson(song as Map<String, dynamic>);
      }).toList();
    }
    return [];
  }

  Future<List<Song>> getSuggestions() async {
    final result = await _api.get('/suggestions');
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items = result['data'] as List<dynamic>? ?? [];
      return items.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
