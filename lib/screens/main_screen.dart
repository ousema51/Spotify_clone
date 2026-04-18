import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/music_service.dart';
import '../services/network_status_service.dart';
import '../services/offline_audio_cache_service.dart';
import '../services/offline_library_service.dart';
import '../services/player_service.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

enum LibraryView { library, likedSongs, playlist }

enum BrowseView { none, artist, album }

enum QueueRepeatMode { off, playlist, song }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Song? _currentSong;
  final ValueNotifier<Song?> _currentSongNotifier = ValueNotifier<Song?>(null);
  final ValueNotifier<int> _fullPlayerUiRevision = ValueNotifier<int>(0);
  final AuthService _authService = AuthService();
  final MusicService _musicService = MusicService();
  final PlayerService _player = PlayerService();
  final OfflineAudioCacheService _audioCache = OfflineAudioCacheService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  int _playRequestNonce = 0;
  final List<Song> _playQueue = [];
  final List<Song> _playbackHistory = [];
  int _queueIndex = -1;
  bool _isFullPlayerOpen = false;
  bool _isShuffleEnabled = false;
  QueueRepeatMode _repeatMode = QueueRepeatMode.off;
  final Set<String> _favoriteSongIds = <String>{};
  bool _favoriteActionInFlight = false;
  bool _isCurrentSongFavorite = false;
  PlayerPlaybackState _lastObservedPlaybackState = PlayerPlaybackState.idle;
  int _favoriteStatusRequestNonce = 0;
  int _prebufferGeneration = 0;
  Set<String> _prebufferAttemptedKeys = <String>{};

  final List<Song> _queuedSongs = [];

  LibraryView _libraryView = LibraryView.library;
  String? _activePlaylistId;
  int _libraryRefreshKey = 0;
  BrowseView _browseView = BrowseView.none;
  String? _activeArtistId;
  String? _activeAlbumId;

  void _markFullPlayerUiDirty() {
    _fullPlayerUiRevision.value = _fullPlayerUiRevision.value + 1;
  }

  @override
  void initState() {
    super.initState();
    _lastObservedPlaybackState = _player.playbackStateNotifier.value;
    _player.playbackStateNotifier.addListener(_handlePlaybackStateChange);
  }

  void _setCurrentSong(Song? song) {
    _currentSong = song;
    _currentSongNotifier.value = song;

    if (song == null) {
      _cancelSequentialPrebuffering();
      _isCurrentSongFavorite = false;
      _markFullPlayerUiDirty();
      return;
    }

    final songId = song.id.trim();
    _isCurrentSongFavorite =
        songId.isNotEmpty && _favoriteSongIds.contains(songId);
    _markFullPlayerUiDirty();
    unawaited(_loadFavoriteStateForSong(song));
    _restartSequentialPrebuffering();
  }

  void _handlePlaybackStateChange() {
    final nextState = _player.playbackStateNotifier.value;
    final isFreshCompletion =
        nextState == PlayerPlaybackState.completed &&
        _lastObservedPlaybackState != PlayerPlaybackState.completed;
    _lastObservedPlaybackState = nextState;

    if (!mounted) {
      return;
    }

    if (isFreshCompletion) {
      unawaited(_handleTrackCompleted());
    }
  }

  Future<void> _handleTrackCompleted() async {
    if (_currentSong == null) {
      return;
    }

    if (_repeatMode == QueueRepeatMode.song) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    await _playNextSong(showErrorWhenUnavailable: false);
  }

  List<Song> _effectiveQueue() {
    if (_playQueue.isNotEmpty) {
      return List<Song>.from(_playQueue);
    }

    if (_queuedSongs.isNotEmpty) {
      return List<Song>.from(_queuedSongs);
    }

    final current = _currentSong;
    if (current != null) {
      return [current];
    }

    return const <Song>[];
  }

  int _indexInQueue(List<Song> queue, Song? song) {
    if (song == null) {
      return -1;
    }
    return queue.indexWhere((candidate) => _sameSong(candidate, song));
  }

  int _indexInQueueByIdentity(List<Song> queue, Song? song) {
    if (song == null) {
      return -1;
    }
    return queue.indexWhere((candidate) => identical(candidate, song));
  }

  int _findQueueIndexForSong(List<Song> queue, Song song) {
    final identityIndex = _indexInQueueByIdentity(queue, song);
    if (identityIndex >= 0) {
      return identityIndex;
    }
    return _indexInQueue(queue, song);
  }

  int _resolveCurrentQueueIndex(List<Song> queue, Song? currentSong) {
    if (currentSong == null || queue.isEmpty) {
      return -1;
    }

    if (_queueIndex >= 0 && _queueIndex < queue.length) {
      if (identical(queue[_queueIndex], currentSong)) {
        return _queueIndex;
      }
    }

    final identityIndex = _indexInQueueByIdentity(queue, currentSong);
    if (identityIndex >= 0) {
      return identityIndex;
    }

    return _indexInQueue(queue, currentSong);
  }

  void _rememberForPrevious(Song? current, Song nextSong) {
    if (current == null || _sameSong(current, nextSong)) {
      return;
    }

    _playbackHistory.add(current);
    if (_playbackHistory.length > 60) {
      _playbackHistory.removeAt(0);
    }
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffleEnabled = !_isShuffleEnabled;
    });
    _markFullPlayerUiDirty();
    _restartSequentialPrebuffering();
  }

  void _cycleRepeatMode() {
    setState(() {
      switch (_repeatMode) {
        case QueueRepeatMode.off:
          _repeatMode = QueueRepeatMode.playlist;
          break;
        case QueueRepeatMode.playlist:
          _repeatMode = QueueRepeatMode.song;
          break;
        case QueueRepeatMode.song:
          _repeatMode = QueueRepeatMode.off;
          break;
      }
    });
    _markFullPlayerUiDirty();
    _restartSequentialPrebuffering();
  }

  String _repeatModeLabel() {
    switch (_repeatMode) {
      case QueueRepeatMode.off:
        return 'Loop off';
      case QueueRepeatMode.playlist:
        return 'Loop playlist';
      case QueueRepeatMode.song:
        return 'Loop current song';
    }
  }

  List<Song> _buildSequentialBufferTargets() {
    final queue = _effectiveQueue();
    final current = _currentSong;

    if (queue.isEmpty || current == null) {
      return const <Song>[];
    }

    final currentIndex = _resolveCurrentQueueIndex(queue, current);
    if (currentIndex < 0) {
      return List<Song>.from(queue);
    }

    final targets = <Song>[];

    if (_isShuffleEnabled) {
      for (var i = 0; i < queue.length; i++) {
        if (i != currentIndex) {
          targets.add(queue[i]);
        }
      }
      return targets;
    }

    for (var i = currentIndex + 1; i < queue.length; i++) {
      targets.add(queue[i]);
    }

    if (_repeatMode == QueueRepeatMode.playlist && queue.length > 1) {
      for (var i = 0; i < currentIndex; i++) {
        targets.add(queue[i]);
      }
    }

    return targets;
  }

  void _cancelSequentialPrebuffering() {
    _prebufferGeneration++;
    _prebufferAttemptedKeys = <String>{};
  }

  void _restartSequentialPrebuffering() {
    final generation = ++_prebufferGeneration;
    _prebufferAttemptedKeys = <String>{};
    unawaited(_runSequentialPrebuffering(generation));
  }

  Future<void> _runSequentialPrebuffering(int generation) async {
    while (mounted && generation == _prebufferGeneration) {
      final targets = _buildSequentialBufferTargets();

      Song? targetSong;
      for (final song in targets) {
        final key = _audioCache.cacheKeyForSong(song);
        if (_prebufferAttemptedKeys.contains(key)) {
          continue;
        }

        _prebufferAttemptedKeys.add(key);
        targetSong = song;
        break;
      }

      if (targetSong == null) {
        return;
      }

      try {
        await _audioCache.cacheSongIfMissing(targetSong);
      } catch (_) {
        // Ignore cache warmup failures and continue with remaining tracks.
      }
    }
  }

  Future<void> _loadFavoriteStateForSong(Song song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      return;
    }

    final requestId = ++_favoriteStatusRequestNonce;
    try {
      final liked = await _musicService.checkLiked(songId);
      if (!mounted || requestId != _favoriteStatusRequestNonce) {
        return;
      }

      final current = _currentSong;
      if (current == null || !_sameSong(current, song)) {
        return;
      }

      setState(() {
        _isCurrentSongFavorite = liked;
        if (liked) {
          _favoriteSongIds.add(songId);
        } else {
          _favoriteSongIds.remove(songId);
        }
      });
      _markFullPlayerUiDirty();
    } catch (_) {
      if (!mounted || requestId != _favoriteStatusRequestNonce) {
        return;
      }

      final current = _currentSong;
      if (current == null || !_sameSong(current, song)) {
        return;
      }
    }
  }

  Future<void> _toggleCurrentSongFavorite() async {
    final song = _currentSong;
    if (song == null || _favoriteActionInFlight) {
      return;
    }

    final songId = song.id.trim();
    if (songId.isEmpty) {
      _showPlaybackError('Cannot favorite this song');
      return;
    }

    final nextIsFavorite = !_isCurrentSongFavorite;

    setState(() {
      _favoriteActionInFlight = true;
      _isCurrentSongFavorite = nextIsFavorite;
      if (nextIsFavorite) {
        _favoriteSongIds.add(songId);
      } else {
        _favoriteSongIds.remove(songId);
      }
    });
    _markFullPlayerUiDirty();

    try {
      final isOnline = await _networkStatus.isOnline();
      if (!isOnline) {
        await _queueFavoriteActionForSync(
          song: song,
          isFavorite: nextIsFavorite,
        );
        _showPlaybackInfo('Offline mode: favorite change queued for sync');
        return;
      }

      final response = nextIsFavorite
          ? await _musicService.likeSong(songId, song.toMetadata())
          : await _musicService.unlikeSong(songId);
      if (!mounted) {
        return;
      }

      if (response['success'] != true) {
        final message =
            response['message']?.toString() ?? 'Failed to update favorites';
        if (_looksLikeConnectivityError(message)) {
          await _queueFavoriteActionForSync(
            song: song,
            isFavorite: nextIsFavorite,
          );
          _showPlaybackInfo('Offline mode: favorite change queued for sync');
          return;
        }

        setState(() {
          _isCurrentSongFavorite = !nextIsFavorite;
          if (_isCurrentSongFavorite) {
            _favoriteSongIds.add(songId);
          } else {
            _favoriteSongIds.remove(songId);
          }
        });
        _markFullPlayerUiDirty();

        _showPlaybackError(message);
      } else {
        await _applyFavoriteLocally(song: song, isFavorite: nextIsFavorite);
        await _offlineLibrary.removePendingLikeAction(songId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCurrentSongFavorite = !nextIsFavorite;
          if (_isCurrentSongFavorite) {
            _favoriteSongIds.add(songId);
          } else {
            _favoriteSongIds.remove(songId);
          }
        });
        _markFullPlayerUiDirty();
      }
      _showPlaybackError('Failed to update favorites: $e');
    } finally {
      if (mounted) {
        setState(() {
          _favoriteActionInFlight = false;
        });
        _markFullPlayerUiDirty();
      }
    }
  }

  void _onSongSelected(Song song, [List<Song>? queue]) {
    setState(() {
      _primePlayQueue(song, queue);
      _setCurrentSong(song);
    });
    unawaited(_switchToSelectedSong(song));
    unawaited(_trackListen(song));
  }

  Future<void> _switchToSelectedSong(Song song) async {
    try {
      await _player.stop();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    await _resolveAndPlaySong(song);
  }

  void _primePlayQueue(Song song, [List<Song>? queue]) {
    if (queue != null && queue.isNotEmpty) {
      _playQueue
        ..clear()
        ..addAll(queue);

      final index = _findQueueIndexForSong(_playQueue, song);
      if (index >= 0) {
        _queueIndex = index;
      } else {
        _playQueue.insert(0, song);
        _queueIndex = 0;
      }
      return;
    }

    if (_playQueue.isEmpty) {
      _playQueue.add(song);
      _queueIndex = 0;
      return;
    }

    final existing = _findQueueIndexForSong(_playQueue, song);
    if (existing >= 0) {
      _queueIndex = existing;
      return;
    }

    _playQueue.add(song);
    _queueIndex = _playQueue.length - 1;
  }

  String _buildPlaybackQueryHint(Song song) {
    final parts = <String>[
      if ((song.artist ?? '').trim().isNotEmpty) (song.artist ?? '').trim(),
      if (song.title.trim().isNotEmpty) song.title.trim(),
    ];

    final hint = parts.join(' ').trim();
    if (hint.isNotEmpty) {
      return hint;
    }

    return song.id.trim();
  }

  Future<void> _resolveAndPlaySong(Song song) async {
    final requestId = ++_playRequestNonce;

    try {
      final cachedPath = await _audioCache.getCachedFilePathForSong(song);
      if (!mounted || requestId != _playRequestNonce) {
        return;
      }

      if (cachedPath != null && cachedPath.isNotEmpty) {
        await _player.playLocalFile(song: song, filePath: cachedPath);
        return;
      }

      final streamResult = await _musicService.getStreamDataWithHint(
        song.id,
        queryHint: _buildPlaybackQueryHint(song),
        titleHint: song.title,
      );

      if (!mounted || requestId != _playRequestNonce) {
        return;
      }

      if (streamResult['success'] != true) {
        final message =
            streamResult['message']?.toString() ??
            'Unable to resolve stream data';
        _showPlaybackError(message);
        return;
      }

      final dynamic rawData = streamResult['data'];
      if (rawData is! Map) {
        _showPlaybackError('Invalid stream response payload');
        return;
      }

      final data = Map<String, dynamic>.from(rawData);
      final audioUrl = (data['audio_url']?.toString() ?? '').trim();
      if (audioUrl.isEmpty) {
        _showPlaybackError('Missing audio URL for playback');
        return;
      }

      final rawHeaders = data['headers'];
      final headers = rawHeaders is Map<String, dynamic>
          ? rawHeaders
          : (rawHeaders is Map ? Map<String, dynamic>.from(rawHeaders) : null);

      await _player.playStream(
        song: song,
        audioUrl: audioUrl,
        headers: headers,
      );

      unawaited(() async {
        try {
          await _audioCache.cacheSongFromResolvedData(
            song: song,
            audioUrl: audioUrl,
            headers: headers,
          );
        } catch (_) {}
      }());
    } catch (e) {
      if (!mounted || requestId != _playRequestNonce) {
        return;
      }
      _showPlaybackError('Playback failed: $e');
    }
  }

  void _showPlaybackError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[700]),
    );
  }

  void _showPlaybackInfo(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange[700]),
    );
  }

  bool _looksLikeConnectivityError(String? message) {
    final text = (message ?? '').toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('connection');
  }

  Future<void> _applyFavoriteLocally({
    required Song song,
    required bool isFavorite,
  }) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      return;
    }

    if (isFavorite) {
      await _offlineLibrary.applyLikedSongLocally(song);
    } else {
      await _offlineLibrary.removeLikedSongLocally(songId);
    }
  }

  Future<void> _queueFavoriteActionForSync({
    required Song song,
    required bool isFavorite,
  }) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      return;
    }

    await _applyFavoriteLocally(song: song, isFavorite: isFavorite);
    await _offlineLibrary.queueLikeAction(
      songId: songId,
      like: isFavorite,
      metadata: isFavorite ? song.toMetadata() : null,
    );
  }

  bool get _hasPreviousSong {
    if (_playbackHistory.isNotEmpty) {
      return true;
    }

    final queue = _effectiveQueue();
    final current = _currentSong;
    if (current == null || queue.isEmpty) {
      return false;
    }

    final index = _resolveCurrentQueueIndex(queue, current);
    return index > 0;
  }

  bool get _hasNextSong {
    final queue = _effectiveQueue();
    if (queue.isEmpty) {
      return false;
    }

    if (_isShuffleEnabled && queue.length > 1) {
      return true;
    }

    final current = _currentSong;
    if (current == null) {
      return queue.isNotEmpty;
    }

    final index = _resolveCurrentQueueIndex(queue, current);
    if (index < 0) {
      return queue.length > 1;
    }

    if (index + 1 < queue.length) {
      return true;
    }

    return _repeatMode == QueueRepeatMode.playlist && queue.length > 1;
  }

  Future<void> _togglePlayPause() async {
    if (_currentSong == null) {
      return;
    }

    final state = _player.playbackStateNotifier.value;

    try {
      if (state == PlayerPlaybackState.playing) {
        await _player.pause();
        return;
      }

      if (state == PlayerPlaybackState.paused ||
          state == PlayerPlaybackState.completed) {
        await _player.play();
        return;
      }

      await _resolveAndPlaySong(_currentSong!);
    } catch (e) {
      _showPlaybackError('Playback control failed: $e');
    }
  }

  Future<void> _playNextSong({bool showErrorWhenUnavailable = true}) async {
    final queue = _effectiveQueue();
    final current = _currentSong;

    if (queue.isEmpty || current == null) {
      if (showErrorWhenUnavailable) {
        _showPlaybackError('No next song available in queue');
      }
      return;
    }

    final currentIndex = _resolveCurrentQueueIndex(queue, current);
    int nextIndex = -1;

    if (_isShuffleEnabled && queue.length > 1) {
      final candidates = <int>[];
      for (var i = 0; i < queue.length; i++) {
        if (currentIndex < 0 || i != currentIndex) {
          candidates.add(i);
        }
      }

      if (candidates.isNotEmpty) {
        nextIndex = candidates[Random().nextInt(candidates.length)];
      }
    } else {
      if (currentIndex >= 0 && currentIndex + 1 < queue.length) {
        nextIndex = currentIndex + 1;
      } else if (_repeatMode == QueueRepeatMode.playlist && queue.length > 1) {
        nextIndex = 0;
      }
    }

    if (nextIndex < 0 || nextIndex >= queue.length) {
      if (showErrorWhenUnavailable) {
        _showPlaybackError('No next song available in queue');
      }
      return;
    }

    final nextSong = queue[nextIndex];
    setState(() {
      _rememberForPrevious(current, nextSong);
      _queueIndex = nextIndex;
      _setCurrentSong(nextSong);
    });

    await _resolveAndPlaySong(nextSong);
    unawaited(_trackListen(nextSong));
  }

  Future<void> _playPreviousSong() async {
    if (_playbackHistory.isNotEmpty) {
      final previousSong = _playbackHistory.removeLast();
      setState(() {
        final playQueueIndex = _findQueueIndexForSong(_playQueue, previousSong);
        if (playQueueIndex >= 0) {
          _queueIndex = playQueueIndex;
        }
        _setCurrentSong(previousSong);
      });
      await _resolveAndPlaySong(previousSong);
      unawaited(_trackListen(previousSong));
      return;
    }

    final queue = _effectiveQueue();
    final current = _currentSong;
    if (queue.isEmpty || current == null) {
      _showPlaybackError('No previous song available in queue');
      return;
    }

    final currentIndex = _resolveCurrentQueueIndex(queue, current);
    if (currentIndex > 0) {
      final previousSong = queue[currentIndex - 1];
      setState(() {
        _queueIndex = currentIndex - 1;
        _setCurrentSong(previousSong);
      });
      await _resolveAndPlaySong(previousSong);
      unawaited(_trackListen(previousSong));
      return;
    }

    _showPlaybackError('No previous song available in queue');
  }

  List<Song> _buildUpNextSongs() {
    final queue = _effectiveQueue();
    final current = _currentSong;
    if (queue.isEmpty || current == null) {
      return const <Song>[];
    }

    final currentIndex = _resolveCurrentQueueIndex(queue, current);
    if (currentIndex < 0) {
      return List<Song>.from(queue);
    }

    final upNext = <Song>[];
    if (_isShuffleEnabled) {
      for (var i = 0; i < queue.length; i++) {
        if (i != currentIndex) {
          upNext.add(queue[i]);
        }
      }
      return upNext;
    }

    for (var i = currentIndex + 1; i < queue.length; i++) {
      upNext.add(queue[i]);
    }

    if (_repeatMode == QueueRepeatMode.playlist && queue.length > 1) {
      for (var i = 0; i < currentIndex; i++) {
        upNext.add(queue[i]);
      }
    }

    return upNext;
  }

  Song? _peekNextSong() {
    final upNext = _buildUpNextSongs();
    if (upNext.isEmpty) {
      return null;
    }
    return upNext.first;
  }

  void _showUpNextSheet(BuildContext pageContext) {
    final upNext = _buildUpNextSongs();
    showModalBottomSheet<void>(
      context: pageContext,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        if (upNext.isEmpty) {
          return const SafeArea(
            child: SizedBox(
              height: 140,
              child: Center(
                child: Text(
                  'No upcoming song in queue',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Up Next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${upNext.length}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: upNext.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    itemBuilder: (context, index) {
                      final nextSong = upNext[index];
                      final isNextImmediate = index == 0;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: isNextImmediate
                            ? const Icon(
                                Icons.play_arrow_rounded,
                                color: Color(0xFF9EC2FF),
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        title: Text(
                          nextSong.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          (nextSong.artist ?? 'Unknown Artist').trim().isEmpty
                              ? 'Unknown Artist'
                              : nextSong.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _onSongSelected(nextSong, _effectiveQueue());
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDurationLabel(Duration duration) {
    var safe = duration;
    if (safe.isNegative) {
      safe = Duration.zero;
    }

    final totalSeconds = safe.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Duration _effectiveDurationForSong(Song song, Duration liveDuration) {
    if (liveDuration > Duration.zero) {
      return liveDuration;
    }

    final fallbackSeconds = song.duration ?? 0;
    if (fallbackSeconds <= 0) {
      return Duration.zero;
    }

    return Duration(seconds: fallbackSeconds);
  }

  Future<void> _openFullPlayer() async {
    if (_currentSongNotifier.value == null || _isFullPlayerOpen || !mounted) {
      return;
    }

    _isFullPlayerOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => _buildFullPlayerPage(pageContext),
      ),
    );
    _isFullPlayerOpen = false;
  }

  Widget _buildSongArtwork(
    Song song, {
    required double size,
    required double borderRadius,
  }) {
    final coverUrl = (song.coverUrl ?? '').trim();

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B3B8C), Color(0xFF071D49)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: size * 0.45,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );

    if (coverUrl.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }

  Widget _buildMiniProgressBar(Song song) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _player.positionNotifier,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: _player.durationNotifier,
          builder: (context, duration, child) {
            final effectiveDuration = _effectiveDurationForSong(song, duration);
            final totalMs = effectiveDuration.inMilliseconds;
            final currentMs = position.inMilliseconds;
            final fraction = totalMs > 0
                ? (currentMs / totalMs).clamp(0.0, 1.0)
                : 0.0;

            return ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: fraction,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF0B3B8C),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFullPlayerSeekBar(Song song) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _player.positionNotifier,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: _player.durationNotifier,
          builder: (context, duration, child) {
            final effectiveDuration = _effectiveDurationForSong(song, duration);
            final maxMs = effectiveDuration.inMilliseconds > 0
                ? effectiveDuration.inMilliseconds.toDouble()
                : 1.0;
            final clampedPositionMs = position.inMilliseconds
                .clamp(0, maxMs.toInt())
                .toDouble();

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF0B3B8C),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                    thumbColor: Colors.white,
                    overlayColor: const Color(
                      0xFF0B3B8C,
                    ).withValues(alpha: 0.15),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    min: 0,
                    max: maxMs,
                    value: clampedPositionMs,
                    onChanged: effectiveDuration > Duration.zero
                        ? (value) {
                            unawaited(
                              _player.seek(
                                Duration(milliseconds: value.round()),
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDurationLabel(position),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatDurationLabel(effectiveDuration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFullPlayerPage(BuildContext pageContext) {
    final width = MediaQuery.of(pageContext).size.width;
    final artworkSize = (width - 128).clamp(170.0, 280.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0C1326),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B3B8C), Color(0xFF0A275D), Color(0xFF101010)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<Song?>(
            valueListenable: _currentSongNotifier,
            builder: (context, song, _) {
              if (song == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No active playback',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(pageContext).maybePop(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                );
              }

              return ValueListenableBuilder<int>(
                valueListenable: _fullPlayerUiRevision,
                builder: (context, _, child) {
                  final repeatIcon = _repeatMode == QueueRepeatMode.song
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded;
                  final repeatActive = _repeatMode != QueueRepeatMode.off;
                  final upNextSong = _peekNextSong();
                  final hasUpcoming = upNextSong != null;
                  final rawArtistName = (song.artist ?? '').trim();
                  final artistLabel = rawArtistName.isEmpty
                    ? 'Unknown Artist'
                    : rawArtistName;
                  final canOpenArtist =
                    artistLabel.toLowerCase() != 'unknown artist';

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(pageContext).maybePop(),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    'NOW PLAYING',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      letterSpacing: 1.1,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'From your queue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: _buildSongArtwork(
                                    song,
                                    size: artworkSize,
                                    borderRadius: 22,
                                  ),
                                ),
                                const SizedBox(height: 26),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            song.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 30,
                                              fontWeight: FontWeight.w800,
                                              height: 1.14,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: canOpenArtist
                                                ? () => unawaited(
                                                    _openArtistFromSong(
                                                      song,
                                                      pageContext,
                                                    ),
                                                  )
                                                : null,
                                            child: Text(
                                              artistLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: canOpenArtist
                                                      ? 0.92
                                                      : 0.86,
                                                ),
                                                fontSize: 17,
                                                fontWeight: FontWeight.w500,
                                                decoration: canOpenArtist
                                                    ? TextDecoration.underline
                                                    : TextDecoration.none,
                                                decorationColor: Colors.white
                                                    .withValues(alpha: 0.75),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _queueIndex >= 0 &&
                                                    _playQueue.isNotEmpty
                                                ? 'Track ${_queueIndex + 1} of ${_playQueue.length}'
                                                : (_queuedSongs.isNotEmpty
                                                      ? 'Queue has ${_queuedSongs.length} songs'
                                                      : 'Single track playback'),
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.68,
                                              ),
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          TextButton.icon(
                                            onPressed: hasUpcoming
                                                ? () =>
                                                      _showUpNextSheet(pageContext)
                                                : null,
                                            style: TextButton.styleFrom(
                                              alignment: Alignment.centerLeft,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              foregroundColor: Colors.white,
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.08),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.queue_music_rounded,
                                              size: 18,
                                            ),
                                            label: Text(
                                              hasUpcoming
                                                  ? 'Up Next: ${upNextSong.title}'
                                                  : 'No upcoming song',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    IconButton(
                                      tooltip: _isCurrentSongFavorite
                                          ? 'Remove from favorites'
                                          : 'Add to favorites',
                                      onPressed: _favoriteActionInFlight
                                          ? null
                                          : () => unawaited(
                                              _toggleCurrentSongFavorite(),
                                            ),
                                      icon: Icon(
                                        _isCurrentSongFavorite
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        color: _isCurrentSongFavorite
                                            ? const Color(0xFF9EC2FF)
                                            : Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _buildFullPlayerSeekBar(song),
                                const SizedBox(height: 12),
                                ValueListenableBuilder<PlayerPlaybackState>(
                                  valueListenable: _player.playbackStateNotifier,
                                  builder: (context, state, child) {
                                    final isLoading =
                                        state == PlayerPlaybackState.loading;
                                    final isPlaying =
                                        state == PlayerPlaybackState.playing;

                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          tooltip: _isShuffleEnabled
                                              ? 'Shuffle on'
                                              : 'Shuffle off',
                                          onPressed: _toggleShuffle,
                                          iconSize: 24,
                                          icon: Icon(
                                            Icons.shuffle_rounded,
                                            color: _isShuffleEnabled
                                                ? const Color(0xFF9EC2FF)
                                                : Colors.white,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              onPressed:
                                                  isLoading || !_hasPreviousSong
                                                  ? null
                                                  : () => unawaited(
                                                      _playPreviousSong(),
                                                    ),
                                              iconSize: 38,
                                              color: Colors.white,
                                              icon: const Icon(
                                                Icons.skip_previous_rounded,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            GestureDetector(
                                              onTap: isLoading
                                                  ? null
                                                  : () => unawaited(
                                                      _togglePlayPause(),
                                                    ),
                                              child: Container(
                                                width: 76,
                                                height: 76,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF0B3B8C),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  isPlaying
                                                      ? Icons.pause_rounded
                                                      : Icons.play_arrow_rounded,
                                                  color: Colors.white,
                                                  size: 44,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              onPressed:
                                                  isLoading || !_hasNextSong
                                                  ? null
                                                  : () => unawaited(
                                                      _playNextSong(),
                                                    ),
                                              iconSize: 38,
                                              color: Colors.white,
                                              icon: const Icon(
                                                Icons.skip_next_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                        IconButton(
                                          tooltip: _repeatModeLabel(),
                                          onPressed: _cycleRepeatMode,
                                          iconSize: 24,
                                          icon: Icon(
                                            repeatIcon,
                                            color: repeatActive
                                                ? const Color(0xFF9EC2FF)
                                                : Colors.white,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    final song = _currentSong;
    if (song == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
            gradient: const LinearGradient(
              colors: [Color(0xFF0B3B8C), Color(0xFF14284F), Color(0xFF151515)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_hasNextSong)
                      Text(
                        'Queue preloading',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(8),
                      ),
                      onTap: _openFullPlayer,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
                        child: Row(
                          children: [
                            _buildSongArtwork(song, size: 48, borderRadius: 10),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  ValueListenableBuilder<PlayerPlaybackState>(
                                    valueListenable:
                                        _player.playbackStateNotifier,
                                    builder: (context, state, _) {
                                      return Text(
                                        song.artist ?? 'Unknown Artist',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.78,
                                          ),
                                          fontSize: 12,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.open_in_full_rounded,
                              color: Colors.white.withValues(alpha: 0.78),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ValueListenableBuilder<PlayerPlaybackState>(
                      valueListenable: _player.playbackStateNotifier,
                      builder: (context, state, _) {
                        final isLoading = state == PlayerPlaybackState.loading;
                        final isPlaying = state == PlayerPlaybackState.playing;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: isLoading || !_hasPreviousSong
                                  ? null
                                  : () => unawaited(_playPreviousSong()),
                              icon: const Icon(Icons.skip_previous_rounded),
                              color: Colors.white,
                              tooltip: 'Previous',
                            ),
                            IconButton(
                              onPressed: isLoading
                                  ? null
                                  : () => unawaited(_togglePlayPause()),
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                size: 30,
                              ),
                              color: Colors.white,
                              tooltip: isPlaying ? 'Pause' : 'Play',
                            ),
                            IconButton(
                              onPressed: isLoading || !_hasNextSong
                                  ? null
                                  : () => unawaited(_playNextSong()),
                              icon: const Icon(Icons.skip_next_rounded),
                              color: Colors.white,
                              tooltip: 'Next',
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              _buildMiniProgressBar(song),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _trackListen(Song song) async {
    try {
      await _musicService.trackListen(
        song.id,
        song.toMetadata(),
        0,
        song.duration ?? 0,
      );
    } catch (_) {}
  }

  bool _sameSong(Song a, Song b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty) {
      return a.id == b.id;
    }
    return a.title == b.title && (a.artist ?? '') == (b.artist ?? '');
  }

  Future<bool> _addSongToQueue(Song song, [List<Song>? sourceQueue]) async {
    final alreadyQueued = _queuedSongs.any(
      (existing) => _sameSong(existing, song),
    );
    if (alreadyQueued) {
      return false;
    }

    setState(() {
      _queuedSongs.add(song);
      if (_currentSong == null) {
        _setCurrentSong(song);
      }
    });

    _restartSequentialPrebuffering();

    return true;
  }

  void _openPlaylist(String playlistId) {
    setState(() {
      _activePlaylistId = playlistId;
      _libraryView = LibraryView.playlist;
      _selectedIndex = 2;
    });
  }

  void _openLikedSongs() {
    setState(() {
      _libraryView = LibraryView.likedSongs;
      _selectedIndex = 2;
    });
  }

  void _closeLibrarySubView({bool refresh = false}) {
    setState(() {
      _libraryView = LibraryView.library;
      _activePlaylistId = null;
      if (refresh) {
        _libraryRefreshKey++;
      }
    });
  }

  void _openArtist(String artistId) {
    setState(() {
      _activeArtistId = artistId;
      _browseView = BrowseView.artist;
    });
  }

  Future<void> _openArtistFromSong(
    Song song,
    BuildContext pageContext,
  ) async {
    final rawArtistName = (song.artist ?? '').trim();
    final artistName = rawArtistName.isEmpty ? 'Unknown Artist' : rawArtistName;
    if (artistName.toLowerCase() == 'unknown artist') {
      _showPlaybackError('Artist page is unavailable for this song');
      return;
    }

    try {
      final artists = await _musicService.searchArtists(artistName);
      if (!mounted) {
        return;
      }

      if (artists.isEmpty) {
        _showPlaybackError('Could not find artist page');
        return;
      }

      final expected = artistName.toLowerCase();
      var selected = artists.first;
      for (final candidate in artists) {
        if (candidate.name.trim().toLowerCase() == expected) {
          selected = candidate;
          break;
        }
      }

      _openArtist(selected.id);
      if (!pageContext.mounted) {
        return;
      }
      if (Navigator.of(pageContext).canPop()) {
        Navigator.of(pageContext).pop();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showPlaybackError('Could not open artist page: $e');
    }
  }

  void _openAlbum(String albumId) {
    setState(() {
      _activeAlbumId = albumId;
      _browseView = BrowseView.album;
    });
  }

  void _closeBrowseView() {
    setState(() {
      _browseView = BrowseView.none;
      _activeArtistId = null;
      _activeAlbumId = null;
    });
  }

  void _openLogin() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
    } catch (_) {
      // Always route to login even if remote logout fails.
    }
    if (mounted) {
      _openLogin();
    }
  }

  @override
  void dispose() {
    _cancelSequentialPrebuffering();
    _player.playbackStateNotifier.removeListener(_handlePlaybackStateChange);
    _currentSongNotifier.dispose();
    _fullPlayerUiRevision.dispose();
    unawaited(_player.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget libraryContent;
    if (_libraryView == LibraryView.playlist && _activePlaylistId != null) {
      libraryContent = PlaylistDetailScreen(
        playlistId: _activePlaylistId!,
        onSongSelected: _onSongSelected,
        onAddToQueue: _addSongToQueue,
        onBack: (refresh) => _closeLibrarySubView(refresh: refresh),
      );
    } else if (_libraryView == LibraryView.likedSongs) {
      libraryContent = LikedSongsScreen(
        onSongSelected: _onSongSelected,
        onAddToQueue: _addSongToQueue,
        onBack: _closeLibrarySubView,
      );
    } else {
      libraryContent = LibraryScreen(
        key: ValueKey('library-$_libraryRefreshKey'),
        onSongSelected: _onSongSelected,
        onOpenPlaylist: _openPlaylist,
        onOpenLikedSongs: _openLikedSongs,
      );
    }

    final pages = [
      HomeScreen(
        onSongSelected: _onSongSelected,
        onArtistSelected: _openArtist,
      ),
      SearchScreen(
        onSongSelected: _onSongSelected,
        onArtistSelected: _openArtist,
        onAlbumSelected: _openAlbum,
      ),
      libraryContent,
    ];

    Widget bodyContent = Expanded(child: pages[_selectedIndex]);

    if (_browseView == BrowseView.artist && _activeArtistId != null) {
      bodyContent = Expanded(
        child: ArtistScreen(
          artistId: _activeArtistId!,
          onSongSelected: _onSongSelected,
          onAlbumSelected: _openAlbum,
        ),
      );
    } else if (_browseView == BrowseView.album && _activeAlbumId != null) {
      bodyContent = Expanded(
        child: AlbumScreen(
          albumId: _activeAlbumId!,
          onSongSelected: _onSongSelected,
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: _selectedIndex == 0
              ? AppBar(
                  backgroundColor: const Color(0xFF121212),
                  elevation: 0,
                  actions: [
                    FutureBuilder<bool>(
                      future: _authService.isLoggedIn(),
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return IconButton(
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                            ),
                            tooltip: 'Logout',
                            onPressed: _logout,
                          );
                        }
                        return TextButton(
                          onPressed: _openLogin,
                          child: const Text(
                            'Log In',
                            style: TextStyle(color: Color(0xFF0B3B8C)),
                          ),
                        );
                      },
                    ),
                  ],
                )
              : null,
          body: Column(
            children: [
              bodyContent,
              if (_currentSong != null) _buildPlaybackControls(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() {
              _selectedIndex = index;
              _browseView = BrowseView.none;
              _activeArtistId = null;
              _activeAlbumId = null;
              if (index != 2) {
                _libraryView = LibraryView.library;
                _activePlaylistId = null;
              }
            }),
            backgroundColor: const Color(0xFF1A1A1A),
            selectedItemColor: const Color(0xFF0B3B8C),
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
            ],
          ),
        ),
        if (_browseView != BrowseView.none)
          Positioned(
            top: 12,
            left: 10,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: _closeBrowseView,
              ),
            ),
          ),
      ],
    );
  }
}
