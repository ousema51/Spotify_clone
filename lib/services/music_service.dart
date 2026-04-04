import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'api_service.dart';
import 'package:flutter/foundation.dart';
// Player is unused here; playback handled by PlayerService when needed

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final ApiService _api = ApiService();
  // PlayerService instance not required in this service

  // --- Search ---
  Future<List<Song>> searchSongs(String query) async {
    final result = await _api.get(
      '/music/search?q=${Uri.encodeComponent(query)}&type=songs',
    );
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items = result['data'] is List ? result['data'] : [];
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Album>> searchAlbums(String query) async {
    final result = await _api.get(
      '/music/search?q=${Uri.encodeComponent(query)}&type=albums',
    );
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items = result['data'] is List ? result['data'] : [];
      return items
          .map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Artist>> searchArtists(String query) async {
    final result = await _api.get(
      '/music/search?q=${Uri.encodeComponent(query)}&type=artists',
    );
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items = result['data'] is List ? result['data'] : [];
      return items
          .map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // --- Stream URL (resolved on device, not backend) ---
  Future<String?> getStreamUrl(String songId) async {
    try {
      final res = await _api.get('/music/stream/$songId');
      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        final audioUrl = data['audio_url']?.toString();
        if (audioUrl != null && audioUrl.isNotEmpty) return audioUrl;
      }
    } catch (e) {
      debugPrint('Error fetching stream URL: $e');
    }
    // Fallback to device resolver
    // Device-side stream resolution removed; return null
    return null;
  }

  Future<String?> getStreamUrlWithHint(String songId, String? titleHint) async {
    try {
      final q = titleHint != null && titleHint.isNotEmpty
          ? '?q=${Uri.encodeComponent(titleHint)}'
          : '';
      final res = await _api.get('/music/stream/$songId$q');
      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        final audioUrl = data['audio_url']?.toString();
        if (audioUrl != null && audioUrl.isNotEmpty) return audioUrl;
      }
    } catch (e) {
      debugPrint('Error fetching stream URL with hint: $e');
    }
    // Device-side stream resolution removed; return null
    return null;
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
      final List<dynamic> items = data is List
          ? data
          : (data['songs'] ?? data['trending'] ?? []);
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // --- Library ---
  Future<Map<String, dynamic>> likeSong(
    String songId,
    Map<String, dynamic> metadata,
  ) async {
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
      final List<dynamic> items = data is List
          ? data
          : (data is Map<String, dynamic>
                ? (data['songs'] as List<dynamic>? ?? [])
                : []);
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // --- Playlists ---
  Future<List<Map<String, dynamic>>> getMyPlaylists() async {
    final result = await _api.get('/playlists/mine');
    if (result['success'] == true && result['data'] != null) {
      final List<dynamic> items = result['data'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createPlaylist(String name,
      {String description = '', bool isPublic = true}) async {
    return _api.post('/playlists', {
      'name': name,
      'description': description,
      'is_public': isPublic,
    });
  }

  Future<Map<String, dynamic>> addSongToPlaylist(
    String playlistId,
    Song song,
  ) async {
    return _api.post('/playlists/$playlistId/songs', {
      'song_id': song.id,
      'title': song.title,
      'artist': song.artist,
      'cover_url': song.coverUrl,
      'duration': song.duration,
    });
  }

  Future<Map<String, dynamic>?> getPlaylist(String playlistId) async {
    final result = await _api.get('/playlists/$playlistId');
    if (result['success'] == true && result['data'] != null) {
      return Map<String, dynamic>.from(result['data']);
    }
    return null;
  }

  Future<Map<String, dynamic>> renamePlaylist(
    String playlistId,
    String name,
  ) async {
    return _api.put('/playlists/$playlistId', {
      'name': name,
    });
  }

  Future<Map<String, dynamic>> deletePlaylist(String playlistId) async {
    return _api.delete('/playlists/$playlistId');
  }

  Future<Map<String, dynamic>> removeSongFromPlaylist(
    String playlistId,
    String songId,
  ) async {
    return _api.delete('/playlists/$playlistId/songs/$songId');
  }

  // --- History / Suggestions ---
  Future<Map<String, dynamic>> trackListen(
    String songId,
    Map<String, dynamic> metadata,
    int listenedSeconds,
    int totalDuration,
  ) async {
    return _api.post('/listen/track', {
      'song_id': songId,
      // Backend expects this key; using "metadata" is ignored server-side.
      'song_metadata': metadata,
      'listened_seconds': listenedSeconds,
      'total_duration': totalDuration,
    });
  }

  Future<List<Song>> getRecentHistory() async {
    final result = await _api.get('/history/recent');
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      final List<dynamic> items = data is List
          ? data
          : (data is Map<String, dynamic>
                ? (data['songs'] as List<dynamic>? ?? [])
                : []);
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
