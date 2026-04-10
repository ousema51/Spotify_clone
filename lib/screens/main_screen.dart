import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/music_service.dart';
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
  final AuthService _authService = AuthService();
  final MusicService _musicService = MusicService();
  final PlayerService _player = PlayerService();
  int _playRequestNonce = 0;
  final List<Song> _playQueue = [];
  final List<Song> _playbackHistory = [];
  int _queueIndex = -1;
  bool _isFullPlayerOpen = false;
  bool _isShuffleEnabled = false;
  QueueRepeatMode _repeatMode = QueueRepeatMode.off;
  final Set<String> _favoriteSongIds = <String>{};
  bool _isFavoriteStateLoading = false;
  bool _favoriteActionInFlight = false;
  bool _isCurrentSongFavorite = false;
  int _favoriteStatusRequestNonce = 0;

  final List<Song> _queuedSongs = [];

  LibraryView _libraryView = LibraryView.library;
  String? _activePlaylistId;
  int _libraryRefreshKey = 0;
  BrowseView _browseView = BrowseView.none;
  String? _activeArtistId;
  String? _activeAlbumId;

  @override
  void initState() {
    super.initState();
    _player.playbackStateNotifier.addListener(_handlePlaybackStateChange);
  }

  void _setCurrentSong(Song? song) {
    _currentSong = song;
    _currentSongNotifier.value = song;

    if (song == null) {
      _isCurrentSongFavorite = false;
      _isFavoriteStateLoading = false;
      return;
    }

    final songId = song.id.trim();
    _isCurrentSongFavorite =
        songId.isNotEmpty && _favoriteSongIds.contains(songId);
    _isFavoriteStateLoading = songId.isNotEmpty;
    unawaited(_loadFavoriteStateForSong(song));
  }

  void _handlePlaybackStateChange() {
    if (!mounted) {
      return;
    }

    if (_player.playbackStateNotifier.value == PlayerPlaybackState.completed) {
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

  Future<void> _loadFavoriteStateForSong(Song song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      if (mounted) {
        setState(() {
          _isFavoriteStateLoading = false;
        });
      }
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
        _isFavoriteStateLoading = false;
        _isCurrentSongFavorite = liked;
        if (liked) {
          _favoriteSongIds.add(songId);
        } else {
          _favoriteSongIds.remove(songId);
        }
      });
    } catch (_) {
      if (!mounted || requestId != _favoriteStatusRequestNonce) {
        return;
      }

      final current = _currentSong;
      if (current == null || !_sameSong(current, song)) {
        return;
      }

      setState(() {
        _isFavoriteStateLoading = false;
      });
    }
  }

  Future<void> _addCurrentSongToFavorites() async {
    final song = _currentSong;
    if (song == null || _favoriteActionInFlight) {
      return;
    }

    final songId = song.id.trim();
    if (songId.isEmpty) {
      _showPlaybackError('Cannot favorite this song');
      return;
    }

    if (_isCurrentSongFavorite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Song already in favorites')),
      );
      return;
    }

    setState(() {
      _favoriteActionInFlight = true;
    });

    try {
      final response = await _musicService.likeSong(songId, song.toMetadata());
      if (!mounted) {
        return;
      }

      if (response['success'] == true) {
        setState(() {
          _isCurrentSongFavorite = true;
          _favoriteSongIds.add(songId);
          _isFavoriteStateLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to favorites')));
      } else {
        final message =
            response['message']?.toString() ?? 'Failed to add to favorites';
        _showPlaybackError(message);
      }
    } catch (e) {
      _showPlaybackError('Failed to add to favorites: $e');
    } finally {
      if (mounted) {
        setState(() {
          _favoriteActionInFlight = false;
        });
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

      final index = _playQueue.indexWhere(
        (candidate) => _sameSong(candidate, song),
      );
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

    final existing = _playQueue.indexWhere(
      (candidate) => _sameSong(candidate, song),
    );
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

  bool get _hasPreviousSong {
    if (_playbackHistory.isNotEmpty) {
      return true;
    }

    final queue = _effectiveQueue();
    final current = _currentSong;
    if (current == null || queue.isEmpty) {
      return false;
    }

    final index = _indexInQueue(queue, current);
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

    final index = _indexInQueue(queue, current);
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

    final currentIndex = _indexInQueue(queue, current);
    int nextIndex = -1;

    if (_isShuffleEnabled && queue.length > 1) {
      final candidates = <int>[];
      for (var i = 0; i < queue.length; i++) {
        if (i != currentIndex) {
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
      final playQueueIndex = _indexInQueue(_playQueue, nextSong);
      _queueIndex = playQueueIndex >= 0 ? playQueueIndex : nextIndex;
      _setCurrentSong(nextSong);
    });

    await _resolveAndPlaySong(nextSong);
    unawaited(_trackListen(nextSong));
  }

  Future<void> _playPreviousSong() async {
    if (_playbackHistory.isNotEmpty) {
      final previousSong = _playbackHistory.removeLast();
      setState(() {
        final playQueueIndex = _indexInQueue(_playQueue, previousSong);
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

    final currentIndex = _indexInQueue(queue, current);
    if (currentIndex > 0) {
      final previousSong = queue[currentIndex - 1];
      setState(() {
        final playQueueIndex = _indexInQueue(_playQueue, previousSong);
        _queueIndex = playQueueIndex >= 0 ? playQueueIndex : currentIndex - 1;
        _setCurrentSong(previousSong);
      });
      await _resolveAndPlaySong(previousSong);
      unawaited(_trackListen(previousSong));
      return;
    }

    _showPlaybackError('No previous song available in queue');
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

              final repeatIcon = _repeatMode == QueueRepeatMode.song
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded;
              final repeatActive = _repeatMode != QueueRepeatMode.off;

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(pageContext).maybePop(),
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
                                      Text(
                                        song.artist ?? 'Unknown Artist',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.86,
                                          ),
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
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
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isCurrentSongFavorite
                                        ? const Color(0xFF356DCE)
                                        : Colors.white.withValues(alpha: 0.09),
                                    border: Border.all(
                                      color: _isCurrentSongFavorite
                                          ? const Color(0xFF9EC2FF)
                                          : Colors.white.withValues(
                                              alpha: 0.22,
                                            ),
                                    ),
                                  ),
                                  child: IconButton(
                                    tooltip: _isCurrentSongFavorite
                                        ? 'Already in favorites'
                                        : 'Add to favorites',
                                    onPressed: _favoriteActionInFlight
                                        ? null
                                        : () => unawaited(
                                            _addCurrentSongToFavorites(),
                                          ),
                                    icon:
                                        _favoriteActionInFlight ||
                                            _isFavoriteStateLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            _isCurrentSongFavorite
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            color: Colors.white,
                                            size: 27,
                                          ),
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
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isShuffleEnabled
                                            ? const Color(0xFF356DCE)
                                            : Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                        border: Border.all(
                                          color: _isShuffleEnabled
                                              ? const Color(0xFF9EC2FF)
                                              : Colors.white.withValues(
                                                  alpha: 0.18,
                                                ),
                                        ),
                                      ),
                                      child: IconButton(
                                        tooltip: _isShuffleEnabled
                                            ? 'Shuffle on'
                                            : 'Shuffle off',
                                        onPressed: _toggleShuffle,
                                        iconSize: 24,
                                        icon: const Icon(
                                          Icons.shuffle_rounded,
                                          color: Colors.white,
                                        ),
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
                                            child: isLoading
                                                ? const Padding(
                                                    padding: EdgeInsets.all(22),
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 3,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Icon(
                                                    isPlaying
                                                        ? Icons.pause_rounded
                                                        : Icons
                                                              .play_arrow_rounded,
                                                    color: Colors.white,
                                                    size: 44,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          onPressed: isLoading || !_hasNextSong
                                              ? null
                                              : () =>
                                                    unawaited(_playNextSong()),
                                          iconSize: 38,
                                          color: Colors.white,
                                          icon: const Icon(
                                            Icons.skip_next_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            _repeatMode == QueueRepeatMode.song
                                            ? const Color(0xFF4D7ED4)
                                            : (repeatActive
                                                  ? const Color(0xFF356DCE)
                                                  : Colors.white.withValues(
                                                      alpha: 0.08,
                                                    )),
                                        border: Border.all(
                                          color: repeatActive
                                              ? const Color(0xFF9EC2FF)
                                              : Colors.white.withValues(
                                                  alpha: 0.18,
                                                ),
                                        ),
                                      ),
                                      child: IconButton(
                                        tooltip: _repeatModeLabel(),
                                        onPressed: _cycleRepeatMode,
                                        iconSize: 24,
                                        icon: Icon(
                                          repeatIcon,
                                          color: Colors.white,
                                        ),
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
                                      final isLoading =
                                          state == PlayerPlaybackState.loading;
                                      if (isLoading) {
                                        return Row(
                                          children: [
                                            const SizedBox(
                                              width: 10,
                                              height: 10,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Buffering',
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.78,
                                                ),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        );
                                      }

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
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
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
    _player.playbackStateNotifier.removeListener(_handlePlaybackStateChange);
    _currentSongNotifier.dispose();
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
      HomeScreen(onSongSelected: _onSongSelected),
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
