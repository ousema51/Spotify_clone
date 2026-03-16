import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'api_service.dart';
import 'player_service.dart';

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final ApiService _api = ApiService();
  final PlayerService _player = PlayerService();

  // --- Search ---
  Future<List<Song>> searchSongs(String query) async {
    final result = await _api.get(
        '/music/search?q=${Uri.encodeComponent(query)}&type=songs');
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items =
          result['data'] is List ? result['data'] : [];
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Album>> searchAlbums(String query) async {
    final result = await _api.get(
        '/music/search?q=${Uri.encodeComponent(query)}&type=albums');
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items =
          result['data'] is List ? result['data'] : [];
      return items
          .map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Artist>> searchArtists(String query) async {
    final result = await _api.get(
        '/music/search?q=${Uri.encodeComponent(query)}&type=artists');
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items =
          result['data'] is List ? result['data'] : [];
      return items
          .map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // --- Stream URL (resolved on device, not backend) ---
  Future<String?> getStreamUrl(String songId) async {
    // Prefer backend-resolved stream URL when available
    final res = await _api.get('/music/stream/$songId');
    if (res['success'] == true && res['data'] != null) {
      return (res['data']['stream_url'] ?? res['data']['streamUrl'])?.toString();
    }
    // Fallback to device resolver
    return _player.resolveStreamUrl(songId);
  }

  Future<String?> getStreamUrlWithHint(
      String songId, String? titleHint) async {
    // Try backend stream resolver with optional title hint to improve accuracy
    final q = titleHint != null && titleHint.isNotEmpty
        ? '?q=${Uri.encodeComponent(titleHint)}'
        : '';
    final res = await _api.get('/music/stream/$songId$q');
    if (res['success'] == true && res['data'] != null) {
      final data = res['data'];
      // Explicit stream URL from backend
      final explicit = (data['stream_url'] ?? data['streamUrl'])?.toString();
      if (explicit != null && explicit.isNotEmpty) return explicit;

      // Backend asks client to resolve via Piped instances
      final videoId = (data['video_id'] ?? data['videoId'])?.toString();
      final piped = data['piped_instances'] ?? data['pipedInstances'];
      final resolveOnClient = data['resolve_on_client'] ?? data['resolveOnClient'];
      if (videoId != null && resolveOnClient == true && piped is List && piped.isNotEmpty) {
        // Use first piped instance to form a streams URL the client can fetch
        final instance = piped.first.toString().replaceAll(RegExp(r'\/$'), '');
        return '$instance/streams/$videoId';
      }
    }
    // Fallback to device resolver
    return _player.resolveStreamUrl(songId);
  }

  // --- Individual fetch ---
  Future<Song?> getSong(String songId) async {
    final result = await _api.get('/music/song/$songId');
    if (result['success'] == true && result['data'] != null) {
      return Song.fromJson(result['data'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<Album?> getAlbum(String albumId) async {
    final result = await _api.get('/music/album/$albumId');
    if (result['success'] == true && result['data'] != null) {
      return Album.fromJson(result['data'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<Artist?> getArtist(String artistId) async {
    final result = await _api.get('/music/artist/$artistId');
    if (result['success'] == true && result['data'] != null) {
      return Artist.fromJson(result['data'] as Map<String, dynamic>);
    }
    return null;
  }

  // --- Trending / Home ---
  Future<List<Song>> getTrending() async {
    final result = await _api.get('/music/trending');
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items =
          data is List ? data : (data['songs'] ?? data['trending'] ?? []);
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
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
      final List<dynamic> items = result['data'] as List<dynamic>? ?? [];
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // --- History / Suggestions ---
  Future<Map<String, dynamic>> trackListen(
      String songId,
      Map<String, dynamic> metadata,
      int listenedSeconds,
      int totalDuration) async {
    return _api.post('/listen/track', {
      'song_id': songId,
      'metadata': metadata,
      'listened_seconds': listenedSeconds,
      'total_duration': totalDuration,
    });
  }

  Future<List<Song>> getRecentHistory() async {
    final result = await _api.get('/history/recent');
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items = result['data'] as List<dynamic>? ?? [];
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
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }
}