import 'dart:async';
import 'dart:convert';

import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'youtube_stream_resolver_stub.dart'
    if (dart.library.io) 'youtube_stream_resolver_io.dart'
    as youtube_stream_resolver;
// Player is unused here; playback handled by PlayerService when needed

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final ApiService _api = ApiService();
  // PlayerService instance not required in this service

  static const String _pipedRegistryUrl = 'https://piped-instances.kavin.rocks';
  static const Duration _pipedRequestTimeout = Duration(seconds: 8);
  static const Duration _pipedRegistryCacheTtl = Duration(minutes: 30);

  static const List<String> _fallbackPipedInstances = [
    'https://api.piped.private.coffee',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.yt',
    'https://pipedapi.r4fo.com',
    'https://pipedapi.leptons.xyz',
  ];

  List<String>? _cachedPipedInstances;
  DateTime? _pipedInstancesFetchedAt;

  static const Map<String, String> _defaultStreamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://music.youtube.com/',
    'Origin': 'https://music.youtube.com',
  };

  String? _normalizeUrl(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return trimmed;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? (double.tryParse(value)?.toInt() ?? 0);
    }
    return 0;
  }

  Map<String, String> _normalizeHeaders(dynamic rawHeaders) {
    final merged = Map<String, String>.from(_defaultStreamHeaders);
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        final k = key.toString().trim();
        final v = value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          merged[k] = v;
        }
      });
    }
    return merged;
  }

  Map<String, dynamic>? _normalizeStreamData(dynamic rawData) {
    if (rawData is! Map) return null;
    final data = Map<String, dynamic>.from(rawData);

    final url = _normalizeUrl(
      data['audio_url']?.toString() ?? data['stream_url']?.toString(),
    );
    if (url == null) return null;

    return {
      'audio_url': url,
      'headers': _normalizeHeaders(data['headers']),
      'source': data['source']?.toString() ?? 'backend',
      if (data['video_id'] != null) 'video_id': data['video_id'].toString(),
      if (data['title'] != null) 'title': data['title'].toString(),
      if (data['duration'] != null) 'duration': _toInt(data['duration']),
    };
  }

  bool _isValidVideoId(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value);
  }

  String? _extractVideoIdFromText(String? value) {
    if (value == null) return null;

    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (_isValidVideoId(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final queryVideoId = uri.queryParameters['v'];
      if (queryVideoId != null && _isValidVideoId(queryVideoId)) {
        return queryVideoId;
      }

      if (uri.pathSegments.isNotEmpty) {
        final lastSegment = uri.pathSegments.last;
        if (_isValidVideoId(lastSegment)) {
          return lastSegment;
        }
      }
    }

    final match = RegExp(r'([A-Za-z0-9_-]{11})').firstMatch(trimmed);
    return match?.group(1);
  }

  String? _extractVideoIdFromPipedItem(Map<String, dynamic> item) {
    final fromId = _extractVideoIdFromText(item['id']?.toString());
    if (fromId != null) return fromId;

    final rawUrl = item['url']?.toString();
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    final normalizedUrl = rawUrl.startsWith('http')
        ? rawUrl
        : 'https://www.youtube.com$rawUrl';
    return _extractVideoIdFromText(normalizedUrl);
  }

  String? _normalizeInstanceUrl(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('https://')) return null;
    return trimmed.replaceFirst(RegExp(r'/$'), '');
  }

  List<String> _dedupeInstances(Iterable<String> rawInstances) {
    final seen = <String>{};
    final normalized = <String>[];

    for (final instance in rawInstances) {
      final cleaned = _normalizeInstanceUrl(instance);
      if (cleaned == null) continue;
      if (seen.add(cleaned)) {
        normalized.add(cleaned);
      }
    }

    return normalized;
  }

  Future<List<String>> _loadPipedInstances() async {
    final now = DateTime.now();
    if (_cachedPipedInstances != null && _pipedInstancesFetchedAt != null) {
      final age = now.difference(_pipedInstancesFetchedAt!);
      if (age < _pipedRegistryCacheTtl && _cachedPipedInstances!.isNotEmpty) {
        return _cachedPipedInstances!;
      }
    }

    final discoveredInstances = <String>[];
    try {
      final response = await http
          .get(
            Uri.parse(_pipedRegistryUrl),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_pipedRequestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final apiUrl =
                item['api_url']?.toString() ?? item['apiUrl']?.toString();
            final normalized = _normalizeInstanceUrl(apiUrl);
            if (normalized != null) {
              discoveredInstances.add(normalized);
            }
          }
        }
      } else {
        debugPrint(
          '[MusicService] Piped registry request failed: ${response.statusCode}',
        );
      }
    } on TimeoutException {
      debugPrint('[MusicService] Piped registry timeout');
    } catch (e) {
      debugPrint('[MusicService] Piped registry lookup failed: $e');
    }

    _cachedPipedInstances = _dedupeInstances([
      ...discoveredInstances,
      ..._fallbackPipedInstances,
    ]);
    _pipedInstancesFetchedAt = now;

    if (_cachedPipedInstances!.isEmpty) {
      _cachedPipedInstances = List<String>.from(_fallbackPipedInstances);
    }

    return _cachedPipedInstances!;
  }

  Map<String, dynamic>? _pickBestPipedAudioStream(dynamic rawStreams) {
    if (rawStreams is! List) return null;

    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final item in rawStreams.whereType<Map>()) {
      final stream = Map<String, dynamic>.from(item);
      final url = _normalizeUrl(
        stream['url']?.toString() ?? stream['audioProxyUrl']?.toString(),
      );
      if (url == null) continue;

      final bitrate = _toInt(stream['bitrate']);
      final codec = (stream['codec']?.toString() ?? '').toLowerCase();

      var score = bitrate;
      if (codec.contains('opus') ||
          codec.contains('aac') ||
          codec.contains('mp4a')) {
        score += 10;
      }

      if (score > bestScore) {
        bestScore = score;
        best = stream;
      }
    }

    return best;
  }

  Future<Map<String, dynamic>?> _resolvePipedStreamByVideoId(
    String songId,
    List<String> instances,
  ) async {
    final videoId = _extractVideoIdFromText(songId);
    if (videoId == null) return null;

    for (final normalizedInstance in instances) {
      final uri = Uri.parse('$normalizedInstance/streams/$videoId');

      try {
        final response = await http.get(uri).timeout(_pipedRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) continue;
        final payload = Map<String, dynamic>.from(decoded);

        final stream = _pickBestPipedAudioStream(payload['audioStreams']);
        if (stream == null) continue;

        var url = _normalizeUrl(
          stream['url']?.toString() ?? stream['audioProxyUrl']?.toString(),
        );
        if (url == null) continue;
        if (url.startsWith('/')) {
          url = '$normalizedInstance$url';
        }

        return {
          'audio_url': url,
          'headers': Map<String, String>.from(_defaultStreamHeaders),
          'source': 'piped',
          'piped_instance': normalizedInstance,
          if (payload['title'] != null) 'title': payload['title'].toString(),
          if (payload['duration'] != null)
            'duration': _toInt(payload['duration']),
          'video_id': videoId,
        };
      } on TimeoutException {
        debugPrint('[MusicService] Piped timeout at $uri');
      } catch (e) {
        debugPrint('[MusicService] Piped stream lookup failed at $uri: $e');
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _resolvePipedStreamBySearch(
    String titleHint,
    List<String> instances,
  ) async {
    final query = titleHint.trim();
    if (query.isEmpty) return null;

    const filters = ['music_songs', 'videos'];

    for (final normalizedInstance in instances) {
      for (final filter in filters) {
        final uri = Uri.parse(
          '$normalizedInstance/search',
        ).replace(queryParameters: {'q': query, 'filter': filter});

        try {
          final response = await http
              .get(uri, headers: const {'Accept': 'application/json'})
              .timeout(_pipedRequestTimeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          final items = decoded is List
              ? decoded
              : (decoded is Map && decoded['items'] is List
                    ? decoded['items'] as List
                    : const <dynamic>[]);

          for (final item in items.take(6)) {
            if (item is! Map) continue;

            final itemMap = Map<String, dynamic>.from(item);
            final resolvedId = _extractVideoIdFromPipedItem(itemMap);
            if (resolvedId == null) continue;

            final resolved = await _resolvePipedStreamByVideoId(resolvedId, [
              normalizedInstance,
            ]);
            if (resolved != null) {
              resolved['source'] = 'piped-search';
              resolved['search_query'] = query;
              return resolved;
            }
          }
        } on TimeoutException {
          debugPrint('[MusicService] Piped search timeout at $uri');
        } catch (e) {
          debugPrint('[MusicService] Piped search failed at $uri: $e');
        }
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _resolvePipedStream(
    String songId, {
    String? titleHint,
  }) async {
    final instances = await _loadPipedInstances();

    final direct = await _resolvePipedStreamByVideoId(songId, instances);
    if (direct != null) {
      return direct;
    }

    final query = (titleHint ?? '').trim();
    if (query.isNotEmpty) {
      final searched = await _resolvePipedStreamBySearch(query, instances);
      if (searched != null) {
        return searched;
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> getStreamDataWithHint(
    String songId,
    String? titleHint,
  ) async {
    final normalizedSongId = _extractVideoIdFromText(songId) ?? songId.trim();
    final normalizedHint = (titleHint ?? '').trim();
    final routeSongId = normalizedSongId.isNotEmpty
        ? normalizedSongId
        : 'search';

    final backendPaths = <String>[
      if (normalizedHint.isNotEmpty)
        '/music/stream/${Uri.encodeComponent(routeSongId)}?q=${Uri.encodeComponent(normalizedHint)}',
      if (normalizedSongId.isNotEmpty)
        '/music/stream/${Uri.encodeComponent(normalizedSongId)}',
    ];

    for (final path in backendPaths) {
      try {
        final res = await _api.get(path).timeout(const Duration(seconds: 8));
        if (res['success'] == true && res['data'] != null) {
          final normalized = _normalizeStreamData(res['data']);
          if (normalized != null) {
            debugPrint('[MusicService] Using backend stream for $path');
            return normalized;
          }
        }
      } catch (e) {
        debugPrint('[MusicService] Backend stream fetch failed ($path): $e');
      }
    }

    final resolvedByYoutube = await youtube_stream_resolver.resolveStream(
      songId: normalizedSongId,
      titleHint: normalizedHint,
      defaultHeaders: _defaultStreamHeaders,
    );
    if (resolvedByYoutube != null) {
      final normalized = _normalizeStreamData(resolvedByYoutube);
      if (normalized != null) {
        final resolvedId = normalized['video_id']?.toString() ?? songId;
        debugPrint(
          '[MusicService] Using youtube_explode fallback for $resolvedId',
        );
        return normalized;
      }
    }

    final piped = await _resolvePipedStream(
      normalizedSongId.isNotEmpty ? normalizedSongId : songId,
      titleHint: normalizedHint,
    );
    if (piped != null) {
      final resolvedId = piped['video_id']?.toString() ?? songId;
      debugPrint('[MusicService] Using Piped fallback for $resolvedId');
      return piped;
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
