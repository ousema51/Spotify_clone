import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'audio_cache_service.dart';

enum QueueRepeatMode { off, all, one }

enum PlayerPlaybackState { idle, loading, playing, paused, completed, error }

class PlayerService {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioCacheService _cache = AudioCacheService();

  static const Map<String, String> _defaultStreamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://music.youtube.com/',
    'Origin': 'https://music.youtube.com',
  };

  StreamSubscription<PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration?>? _audioDurationSubscription;

  Song? _currentSong;
  bool _isPlaying = false;
  bool _isReady = false;
  int _loadGeneration = 0;

  // Listeners for UI updates
  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _readyNotifier = ValueNotifier(false);
  final ValueNotifier<PlayerPlaybackState> _playbackStateNotifier =
      ValueNotifier(PlayerPlaybackState.idle);
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(
    Duration.zero,
  );

  PlayerService._internal() {
    _ensureAudioListeners();
  }

  MediaItem _buildMediaItem(Song song, String sourceId) {
    return MediaItem(
      id: sourceId,
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.albumName ?? 'KoiWave',
      artUri: (song.coverUrl != null && song.coverUrl!.isNotEmpty)
          ? Uri.tryParse(song.coverUrl!)
          : null,
      duration: (song.duration != null && song.duration! > 0)
          ? Duration(seconds: song.duration!)
          : null,
      extras: {'song_id': song.id},
    );
  }

  void _ensureAudioListeners() {
    _audioStateSubscription ??= _audioPlayer.playerStateStream.listen(
      (state) {
        _playbackStateNotifier.value = _mapPlaybackState(state);

        final bool playing =
            state.playing && state.processingState == ProcessingState.ready;
        if (playing != _isPlaying) {
          _isPlaying = playing;
          _playingNotifier.value = _isPlaying;
        }

        final bool ready =
            state.processingState == ProcessingState.ready ||
            state.processingState == ProcessingState.completed;
        if (ready != _isReady) {
          _isReady = ready;
          _readyNotifier.value = _isReady;
        }

        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _playingNotifier.value = false;

          final finishedAt = _audioPlayer.duration;
          if (finishedAt != null && finishedAt > Duration.zero) {
            _positionNotifier.value = finishedAt;
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _playbackStateNotifier.value = PlayerPlaybackState.error;
        debugPrint('[PlayerService] Player stream error: $error');
      },
    );

    _audioPositionSubscription ??= _audioPlayer.positionStream.listen((pos) {
      _positionNotifier.value = pos;
    });

    _audioDurationSubscription ??= _audioPlayer.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _durationNotifier.value = dur;
      }
    });
  }

  PlayerPlaybackState _mapPlaybackState(PlayerState state) {
    switch (state.processingState) {
      case ProcessingState.idle:
        return PlayerPlaybackState.idle;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        return PlayerPlaybackState.loading;
      case ProcessingState.ready:
        return state.playing
            ? PlayerPlaybackState.playing
            : PlayerPlaybackState.paused;
      case ProcessingState.completed:
        return PlayerPlaybackState.completed;
    }
  }

  Map<String, String> _buildStreamHeaders(Map<String, String>? streamHeaders) {
    final merged = <String, String>{..._defaultStreamHeaders};
    if (streamHeaders == null) return merged;

    streamHeaders.forEach((key, value) {
      final k = key.trim();
      final v = value.trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        merged[k] = v;
      }
    });

    return merged;
  }

  bool _isActiveLoad(int generation) => generation == _loadGeneration;

  /// Load a song and start playback using just_audio across platforms.
  Future<void> loadSong(
    Song song, {
    String? streamUrl,
    Map<String, String>? streamHeaders,
  }) async {
    final loadGeneration = ++_loadGeneration;

    _currentSong = song;

    _isReady = false;
    _readyNotifier.value = false;
    _isPlaying = false;
    _playingNotifier.value = false;
    _playbackStateNotifier.value = PlayerPlaybackState.idle;
    _positionNotifier.value = Duration.zero;
    _durationNotifier.value = (song.duration != null && song.duration! > 0)
        ? Duration(seconds: song.duration!)
        : Duration.zero;

    await _audioPlayer.stop();

    if (!_isActiveLoad(loadGeneration)) return;

    final cacheKey = song.id.trim();

    String? cachedPath;
    if (!kIsWeb && cacheKey.isNotEmpty) {
      try {
        cachedPath = await _cache.getCachedFilePath(cacheKey);
      } catch (e) {
        debugPrint('[PlayerService] Cache lookup skipped: $e');
      }
    }

    if (!_isActiveLoad(loadGeneration)) return;

    if (cachedPath != null) {
      try {
        _playbackStateNotifier.value = PlayerPlaybackState.loading;
        final sourceId = Uri.file(cachedPath).toString();
        await _audioPlayer.setAudioSource(
          AudioSource.file(cachedPath, tag: _buildMediaItem(song, sourceId)),
        );
        if (!_isActiveLoad(loadGeneration)) return;

        await _audioPlayer.play();
        if (!_isActiveLoad(loadGeneration)) return;

        debugPrint('[PlayerService] Playing cached audio for: ${song.title}');
        return;
      } catch (e) {
        debugPrint('[PlayerService] Cached playback failed, fallback: $e');
      }
    }

    final resolvedStreamUrl = (streamUrl ?? song.streamUrl ?? '').trim();
    if (resolvedStreamUrl.isEmpty) {
      if (_isActiveLoad(loadGeneration)) {
        _playbackStateNotifier.value = PlayerPlaybackState.error;
      }
      throw StateError('No playable stream URL available for "${song.title}"');
    }

    try {
      _playbackStateNotifier.value = PlayerPlaybackState.loading;
      final mergedHeaders = _buildStreamHeaders(streamHeaders);
      final uri = Uri.parse(resolvedStreamUrl);

      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          uri,
          headers: mergedHeaders,
          tag: _buildMediaItem(song, uri.toString()),
        ),
      );
      if (!_isActiveLoad(loadGeneration)) return;

      await _audioPlayer.play();
      if (!_isActiveLoad(loadGeneration)) return;

      if (!kIsWeb && cacheKey.isNotEmpty) {
        unawaited(
          _cache.cacheInBackground(
            cacheKey,
            resolvedStreamUrl,
            headers: mergedHeaders,
          ),
        );
      }

      debugPrint('[PlayerService] Streaming audio for: ${song.title}');
    } catch (e) {
      if (_isActiveLoad(loadGeneration)) {
        _playbackStateNotifier.value = PlayerPlaybackState.error;
      }
      debugPrint('[PlayerService] Stream playback failed: $e');
      rethrow;
    }
  }

  Future<void> play() async {
    try {
      if (_audioPlayer.audioSource == null) {
        debugPrint('[PlayerService] No audio source loaded');
        return;
      }

      await _audioPlayer.play();
      debugPrint('[PlayerService] Play requested');
    } catch (e) {
      debugPrint('[PlayerService] Play error: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      debugPrint('[PlayerService] Pause requested');
    } catch (e) {
      debugPrint('[PlayerService] Pause error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('[PlayerService] Stop error: $e');
    }
    _isPlaying = false;
    _isReady = false;
    _playingNotifier.value = false;
    _readyNotifier.value = false;
    _playbackStateNotifier.value = PlayerPlaybackState.idle;
    _positionNotifier.value = Duration.zero;
    debugPrint('[PlayerService] Stopped');
  }

  Future<void> seekToFraction(double fraction) async {
    try {
      Duration duration = _durationNotifier.value;

      if (duration <= Duration.zero) {
        final dur = _audioPlayer.duration;
        if (dur != null) {
          duration = dur;
        }

        if (duration > Duration.zero) {
          _durationNotifier.value = duration;
        }
      }

      if (duration <= Duration.zero) return;

      final double clampedFraction = fraction.clamp(0.0, 1.0);
      final Duration target = Duration(
        milliseconds: (duration.inMilliseconds * clampedFraction).round(),
      );

      await _audioPlayer.seek(target);

      _positionNotifier.value = target;
    } catch (e) {
      debugPrint('[PlayerService] Seek error: $e');
    }
  }

  double get progress {
    final total = _durationNotifier.value.inMilliseconds;
    if (total <= 0) return 0.0;
    return (_positionNotifier.value.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Future<void> disposePlayer() async {
    await _audioStateSubscription?.cancel();
    await _audioPositionSubscription?.cancel();
    await _audioDurationSubscription?.cancel();
    _audioStateSubscription = null;
    _audioPositionSubscription = null;
    _audioDurationSubscription = null;

    await _audioPlayer.dispose();
  }

  // Getters
  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  bool get isReady => _isReady;
  Duration get position => _positionNotifier.value;
  Duration get duration => _durationNotifier.value;

  // UI streams for reactive updates
  ValueNotifier<bool> get playingNotifier => _playingNotifier;
  ValueNotifier<bool> get readyNotifier => _readyNotifier;
  ValueNotifier<PlayerPlaybackState> get playbackStateNotifier =>
      _playbackStateNotifier;
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;
  ValueNotifier<Duration> get durationNotifier => _durationNotifier;

  @override
  String toString() =>
      'PlayerService(song: ${_currentSong?.title}, playing: $_isPlaying, ready: $_isReady)';
}
