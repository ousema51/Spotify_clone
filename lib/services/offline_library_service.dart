import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';

class OfflineLibraryService {
  static const String _likedSongsKey = 'offline_liked_songs_v1';
  static const String _playlistsKey = 'offline_playlists_v1';
  static const String _playlistSummariesKey = 'offline_playlist_summaries_v1';
  static const String _albumsKey = 'offline_albums_v1';
  static const String _artistsKey = 'offline_artists_v1';
  static const String _recentAlbumIdsKey = 'offline_recent_album_ids_v1';
  static const String _recentArtistIdsKey = 'offline_recent_artist_ids_v1';
  static const String _pendingLikeActionsKey = 'offline_pending_like_actions_v1';
  static const int _maxRecentAlbums = 20;
  static const int _maxRecentArtists = 20;

  Future<int> cacheLikedSongs(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = songs.map(_songToMap).toList(growable: false);
    await prefs.setString(_likedSongsKey, jsonEncode(payload));
    return payload.length;
  }

  Future<void> applyLikedSongLocally(Song song) async {
    final current = await getCachedLikedSongs();
    final normalizedId = song.id.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final next = current.where((item) => item.id.trim() != normalizedId).toList();
    next.insert(0, song);
    await cacheLikedSongs(next);
  }

  Future<void> removeLikedSongLocally(String songId) async {
    final normalizedId = songId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final current = await getCachedLikedSongs();
    final next =
        current.where((item) => item.id.trim() != normalizedId).toList(growable: false);
    await cacheLikedSongs(next);
  }

  Future<List<Song>> getCachedLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_likedSongsKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> cachePlaylists(List<Map<String, dynamic>> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = playlists
        .map(_playlistSummaryToMap)
        .where((item) => (item['_id'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);

    await prefs.setString(_playlistSummariesKey, jsonEncode(payload));
    return payload.length;
  }

  Future<List<Map<String, dynamic>>> getCachedPlaylists() async {
    return _readList(_playlistSummariesKey);
  }

  Future<int> cachePlaylist(
    String playlistId,
    String playlistName,
    List<Song> songs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readPlaylistsMap();

    all[playlistId] = {
      'name': playlistName,
      'songs': songs.map(_songToMap).toList(growable: false),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_playlistsKey, jsonEncode(all));

    final summaries = await getCachedPlaylists();
    final summary = {
      '_id': playlistId,
      'name': playlistName,
      'songs': songs.map(_songToMap).toList(growable: false),
      'song_count': songs.length,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final nextSummaries = summaries
        .where((item) => (item['_id'] ?? '').toString() != playlistId)
        .toList();
    nextSummaries.insert(0, summary);
    await cachePlaylists(nextSummaries);

    return songs.length;
  }

  Future<Map<String, dynamic>?> getCachedPlaylist(String playlistId) async {
    final all = await _readPlaylistsMap();
    final item = all[playlistId];
    if (item is Map<String, dynamic>) return item;
    return null;
  }

  Future<Map<String, dynamic>> _readPlaylistsMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> cacheAlbumPage(
    Album album, {
    bool markVisited = true,
  }) async {
    final normalizedId = album.id.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final payload = await _readMap(_albumsKey);
    payload[normalizedId] = {
      'album': _albumToMap(album),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _writeMap(_albumsKey, payload);

    if (markVisited) {
      await markAlbumVisited(normalizedId);
    }
  }

  Future<void> markAlbumVisited(String albumId) async {
    final normalizedId = albumId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final recent = await getRecentAlbumIds();
    final next = recent.where((id) => id != normalizedId).toList();
    next.insert(0, normalizedId);

    await prefs.setString(
      _recentAlbumIdsKey,
      jsonEncode(next.take(_maxRecentAlbums).toList(growable: false)),
    );
  }

  Future<List<String>> getRecentAlbumIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentAlbumIdsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .map((item) => item?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Album?> getCachedAlbumPage(String albumId) async {
    final normalizedId = albumId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }

    final payload = await _readMap(_albumsKey);
    final item = payload[normalizedId];
    if (item is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(item);
    final albumJson = map['album'];
    if (albumJson is! Map) {
      return null;
    }

    try {
      return Album.fromJson(Map<String, dynamic>.from(albumJson));
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheArtistPage(
    Artist artist, {
    bool markVisited = true,
  }) async {
    final normalizedId = artist.id.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final payload = await _readMap(_artistsKey);
    payload[normalizedId] = {
      'artist': _artistToMap(artist),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _writeMap(_artistsKey, payload);

    if (markVisited) {
      await markArtistVisited(normalizedId);
    }
  }

  Future<void> markArtistVisited(String artistId) async {
    final normalizedId = artistId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final recent = await getRecentArtistIds();
    final next = recent.where((id) => id != normalizedId).toList();
    next.insert(0, normalizedId);

    await prefs.setString(
      _recentArtistIdsKey,
      jsonEncode(next.take(_maxRecentArtists).toList(growable: false)),
    );
  }

  Future<Artist?> getCachedArtistPage(String artistId) async {
    final normalizedId = artistId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }

    final payload = await _readMap(_artistsKey);
    final item = payload[normalizedId];
    if (item is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(item);
    final artistJson = map['artist'];
    if (artistJson is! Map) {
      return null;
    }

    try {
      return Artist.fromJson(Map<String, dynamic>.from(artistJson));
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> getRecentArtistIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentArtistIdsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .map((item) => item?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Artist>> getRecentArtistPages({int limit = 10}) async {
    final ids = await getRecentArtistIds();
    if (ids.isEmpty || limit <= 0) {
      return const [];
    }

    final artists = <Artist>[];
    for (final id in ids.take(limit)) {
      final artist = await getCachedArtistPage(id);
      if (artist != null) {
        artists.add(artist);
      }
    }

    return artists;
  }

  Future<void> queueLikeAction({
    required String songId,
    required bool like,
    Map<String, dynamic>? metadata,
  }) async {
    final normalizedId = songId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final actions = await getPendingLikeActions();
    final next = actions
        .where((item) => (item['song_id'] ?? '').toString() != normalizedId)
        .toList();

    next.add({
      'song_id': normalizedId,
      'action': like ? 'like' : 'unlike',
      'metadata': metadata ?? <String, dynamic>{},
      'queued_at': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_pendingLikeActionsKey, jsonEncode(next));
  }

  Future<List<Map<String, dynamic>>> getPendingLikeActions() async {
    return _readList(_pendingLikeActionsKey);
  }

  Future<void> clearPendingLikeActions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingLikeActionsKey);
  }

  Future<void> removePendingLikeAction(String songId) async {
    final normalizedId = songId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final actions = await getPendingLikeActions();
    final next = actions
        .where((item) => (item['song_id'] ?? '').toString() != normalizedId)
        .toList(growable: false);

    await prefs.setString(_pendingLikeActionsKey, jsonEncode(next));
  }

  Future<Map<String, dynamic>> _readMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (mapKey, value) => MapEntry(mapKey.toString(), value),
        );
      }
    } catch (_) {}

    return <String, dynamic>{};
  }

  Future<void> _writeMap(String key, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _playlistSummaryToMap(Map<String, dynamic> playlist) {
    final songsRaw = playlist['songs'];
    final songs = <Map<String, dynamic>>[];

    if (songsRaw is List) {
      for (final item in songsRaw) {
        if (item is Map) {
          try {
            songs.add(_songToMap(Song.fromJson(Map<String, dynamic>.from(item))));
          } catch (_) {
            songs.add(Map<String, dynamic>.from(item));
          }
        }
      }
    }

    final id = (playlist['_id'] ?? playlist['id'] ?? '').toString().trim();
    final name = (playlist['name'] ?? 'Untitled Playlist').toString().trim();

    return {
      '_id': id,
      'name': name.isEmpty ? 'Untitled Playlist' : name,
      'songs': songs,
      'song_count': playlist['song_count'] ?? playlist['songCount'] ?? songs.length,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _songToMap(Song song) {
    return {
      'id': song.id,
      'song_id': song.id,
      'name': song.title,
      'title': song.title,
      'artist': song.artist,
      'artists':
          song.artists
              ?.map((name) => {'name': name})
              .toList(growable: false) ??
          (song.artist != null ? [
            {'name': song.artist!}
          ] : []),
      'album': {
        'id': song.albumId,
        'name': song.albumName,
      },
      'image': song.coverUrl,
      'cover_url': song.coverUrl,
      'duration': song.duration,
    };
  }

  Map<String, dynamic> _albumToMap(Album album) {
    return {
      'id': album.id,
      'name': album.title,
      'title': album.title,
      'artist': album.artist,
      'cover_url': album.coverUrl,
      'image': album.coverUrl,
      'song_count': album.songCount ?? album.songs?.length ?? 0,
      'songs':
          album.songs?.map(_songToMap).toList(growable: false) ??
          const <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _artistToMap(Artist artist) {
    return {
      'id': artist.id,
      'name': artist.name,
      'image_url': artist.imageUrl,
      'bio': artist.bio,
      'follower_count': artist.followerCount,
      'top_songs':
          artist.topSongs?.map(_songToMap).toList(growable: false) ??
          const <Map<String, dynamic>>[],
      'top_albums':
          artist.topAlbums?.map(_albumToMap).toList(growable: false) ??
          const <Map<String, dynamic>>[],
    };
  }
}
