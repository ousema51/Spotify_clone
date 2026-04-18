import 'dart:async';

import 'auth_service.dart';
import 'music_service.dart';
import 'network_status_service.dart';
import 'offline_library_service.dart';

class OfflineSyncService {
  OfflineSyncService._internal();
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;

  final AuthService _authService = AuthService();
  final MusicService _musicService = MusicService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final NetworkStatusService _networkStatus = NetworkStatusService();

  StreamSubscription<bool>? _onlineSubscription;
  bool _initialized = false;
  bool _isSyncing = false;

  Future<void> start() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _onlineSubscription = _networkStatus.onlineChanges.listen((isOnline) {
      if (isOnline) {
        unawaited(syncNow());
      }
    });

    final online = await _networkStatus.isOnline();
    if (online) {
      await syncNow();
    }
  }

  Future<void> syncNow() async {
    if (_isSyncing) {
      return;
    }

    final online = await _networkStatus.isOnline();
    if (!online) {
      return;
    }

    final loggedIn = await _authService.isLoggedIn();
    if (!loggedIn) {
      return;
    }

    _isSyncing = true;
    try {
      await _flushPendingLikeActions();
      await _refreshLibraryCaches();
      await _refreshRecentAlbumCaches();
      await _refreshRecentArtistCaches();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _flushPendingLikeActions() async {
    final pending = await _offlineLibrary.getPendingLikeActions();
    for (final action in pending) {
      final songId = (action['song_id'] ?? '').toString().trim();
      if (songId.isEmpty) {
        continue;
      }

      final actionType = (action['action'] ?? '').toString().trim().toLowerCase();
      final metadata = action['metadata'];

      Map<String, dynamic> result;
      if (actionType == 'like') {
        result = await _musicService.likeSong(
          songId,
          metadata is Map<String, dynamic>
              ? metadata
              : (metadata is Map
                    ? Map<String, dynamic>.from(metadata)
                    : <String, dynamic>{}),
        );
      } else {
        result = await _musicService.unlikeSong(songId);
      }

      if (result['success'] == true || _isIdempotentSuccess(actionType, result)) {
        await _offlineLibrary.removePendingLikeAction(songId);
      }
    }
  }

  bool _isIdempotentSuccess(String actionType, Map<String, dynamic> result) {
    final message = (result['message'] ?? '').toString().toLowerCase();
    if (message.isEmpty) {
      return false;
    }

    if (actionType == 'like' && message.contains('already')) {
      return true;
    }

    if (actionType == 'unlike' &&
        (message.contains('not liked') ||
            message.contains('not found') ||
            message.contains('already removed'))) {
      return true;
    }

    return false;
  }

  Future<void> _refreshLibraryCaches() async {
    final likedSongs = await _musicService.getLikedSongs();
    await _offlineLibrary.cacheLikedSongs(likedSongs);

    final playlists = await _musicService.getMyPlaylists();
    await _offlineLibrary.cachePlaylists(playlists);
  }

  Future<void> _refreshRecentArtistCaches() async {
    final recentArtistIds = await _offlineLibrary.getRecentArtistIds();
    for (final artistId in recentArtistIds.take(12)) {
      try {
        final artist = await _musicService.getArtist(artistId);
        if (artist != null) {
          await _offlineLibrary.cacheArtistPage(artist, markVisited: false);
        }
      } catch (_) {
        // Keep syncing remaining artists even if one request fails.
      }
    }
  }

  Future<void> _refreshRecentAlbumCaches() async {
    final recentAlbumIds = await _offlineLibrary.getRecentAlbumIds();
    for (final albumId in recentAlbumIds.take(12)) {
      try {
        final album = await _musicService.getAlbum(albumId);
        if (album != null) {
          await _offlineLibrary.cacheAlbumPage(album, markVisited: false);
        }
      } catch (_) {
        // Keep syncing remaining albums even if one request fails.
      }
    }
  }

  Future<void> dispose() async {
    await _onlineSubscription?.cancel();
    _onlineSubscription = null;
    _initialized = false;
    _isSyncing = false;
  }
}
