import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'api_service.dart';

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final ApiService _api = ApiService();

  static Map<String, dynamic> _normalizeStreamResult(
    Map<String, dynamic> response, {
    String? fallbackVideoId,
    String? fallbackTitle,
  }) {
    if (response['success'] != true) {
      return {
        'success': false,
        'message': response['message']?.toString() ?? 'Stream request failed',
      };
    }

    final dynamic envelope = response['data'];
    if (envelope is! Map) {
      return {
        'success': false,
        'message': 'Invalid stream response data',
      };
    }

    final payload = Map<String, dynamic>.from(envelope);
    final audioUrl =
        (payload['audio_url'] ?? payload['stream_url'] ?? payload['url'])
            ?.toString()
            .trim();
    if (audioUrl == null || audioUrl.isEmpty) {
      return {
        'success': false,
        'message': 'Missing audio_url in stream response',
      };
    }

    final rawHeaders = payload['headers'];
    final Map<String, String> headers = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        final k = key.toString().trim();
        final v = value.toString().trim();
        if (k.isNotEmpty && v.isNotEmpty) {
          headers[k] = v;
        }
      });
    }

    final videoId =
        (payload['video_id'] ??
                payload['videoId'] ??
                payload['id'] ??
                fallbackVideoId)
            ?.toString()
            .trim();

    final title =
        (payload['title'] ?? payload['name'] ?? fallbackTitle)?.toString();

    final duration = _toInt(payload['duration']);
    final source = (payload['source'] ?? 'yt-dlp').toString();

    return {
      'success': true,
      'data': {
        'audio_url': audioUrl,
        'headers': headers,
        'video_id': (videoId?.isEmpty ?? true) ? null : videoId,
        'title': title,
        'duration': duration,
        'source': source,
      },
    };
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    }
    return null;
  }

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

  // --- Streaming JSON contract ---
  Future<Map<String, dynamic>> getStreamDataWithHint(
    String videoId, {
    String? queryHint,
    String? titleHint,
  }) async {
    final cleanVideoId = videoId.trim();
    if (cleanVideoId.isNotEmpty) {
      final response = await _api.get(
        '/music/stream/${Uri.encodeComponent(cleanVideoId)}',
      );
      final normalized = _normalizeStreamResult(
        response,
        fallbackVideoId: cleanVideoId,
        fallbackTitle: titleHint,
      );
      if (normalized['success'] == true) {
        return normalized;
      }
    }

    final cleanHint = queryHint?.trim() ?? '';
    if (cleanHint.isNotEmpty) {
      final fallbackResponse = await _api.get(
        '/music/stream?q=${Uri.encodeComponent(cleanHint)}',
      );
      return _normalizeStreamResult(
        fallbackResponse,
        fallbackVideoId: cleanVideoId.isEmpty ? null : cleanVideoId,
        fallbackTitle: titleHint,
      );
    }

    return {
      'success': false,
      'message': 'Unable to resolve stream data',
    };
  }

  static Map<String, dynamic> normalizeStreamResultForTesting(
    Map<String, dynamic> response, {
    String? fallbackVideoId,
    String? fallbackTitle,
  }) {
    return _normalizeStreamResult(
      response,
      fallbackVideoId: fallbackVideoId,
      fallbackTitle: fallbackTitle,
    );
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

  Future<Map<String, dynamic>> createPlaylist(
    String name, {
    String description = '',
    bool isPublic = true,
  }) async {
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
    return _api.put('/playlists/$playlistId', {'name': name});
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
