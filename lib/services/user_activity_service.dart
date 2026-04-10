import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class UserActivityService {
  UserActivityService._internal();
  static final UserActivityService _instance = UserActivityService._internal();
  factory UserActivityService() => _instance;

  static const String _recentPlaylistsKey = 'recent_playlists_v1';
  static const String _recentSearchSongsKey = 'recent_search_songs_v1';
  static const int _maxRecentPlaylists = 10;
  static const int _maxRecentSongs = 20;

  Future<void> recordPlaylistPlay({
    required String playlistId,
    required String playlistName,
    String? coverUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _readList(_recentPlaylistsKey);

    final filtered = items
        .where((e) => (e['playlist_id'] ?? '').toString() != playlistId)
        .toList();

    filtered.insert(0, {
      'playlist_id': playlistId,
      'name': playlistName,
      'cover_url': coverUrl,
      'played_at': DateTime.now().toIso8601String(),
    });

    final trimmed = filtered.take(_maxRecentPlaylists).toList(growable: false);
    await prefs.setString(_recentPlaylistsKey, jsonEncode(trimmed));
  }

  Future<List<Map<String, dynamic>>> getRecentPlaylists() async {
    return _readList(_recentPlaylistsKey);
  }

  Future<void> recordSearchSongSelection(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _readList(_recentSearchSongsKey);

    final filtered = items
        .where((e) => (e['id'] ?? e['song_id'] ?? '').toString() != song.id)
        .toList();

    filtered.insert(0, {
      'id': song.id,
      'song_id': song.id,
      'title': song.title,
      'artist': song.artist,
      'cover_url': song.coverUrl,
      'duration': song.duration,
      'selected_at': DateTime.now().toIso8601String(),
    });

    final trimmed = filtered.take(_maxRecentSongs).toList(growable: false);
    await prefs.setString(_recentSearchSongsKey, jsonEncode(trimmed));
  }

  Future<List<Song>> getRecentSearchSongs() async {
    final items = await _readList(_recentSearchSongsKey);
    final songs = <Song>[];
    for (final item in items) {
      try {
        final song = Song.fromJson(item);
        if (song.id.isNotEmpty) {
          songs.add(song);
        }
      } catch (_) {
        // Skip malformed cached items instead of failing the full list.
      }
    }
    return songs;
  }

  Future<void> removeRecentSearchSong(String songId) async {
    final normalizedId = songId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final items = await _readList(_recentSearchSongsKey);

    final filtered = items
        .where(
          (e) =>
              (e['id'] ?? e['song_id'] ?? '').toString().trim() != normalizedId,
        )
        .toList(growable: false);

    await prefs.setString(_recentSearchSongsKey, jsonEncode(filtered));
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}

    return [];
  }
}
