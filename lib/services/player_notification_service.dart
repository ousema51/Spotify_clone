import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class PlayerNotificationService extends BaseAudioHandler with SeekHandler {
  PlayerNotificationService._internal();

  static final PlayerNotificationService _instance =
      PlayerNotificationService._internal();
  factory PlayerNotificationService() => _instance;

  static const String _lastSongKey = 'player_notification_last_song_v1';

  bool _initialized = false;

  Future<void> Function()? _onPlayRequested;
  Future<void> Function()? _onPauseRequested;
  Future<void> Function()? _onStopRequested;
  Future<void> Function()? _onSkipToNextRequested;
  Future<void> Function()? _onSkipToPreviousRequested;
  Future<void> Function(Duration position)? _onSeekRequested;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await AudioService.init(
      builder: () => this,
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.koiwave.app.media.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        preloadArtwork: true,
      ),
    );

    _initialized = true;
    await _restoreLastSongForSessionContinuity();
    _pushPlaybackState(
      isPlaying: false,
      isLoading: false,
      isCompleted: false,
      canSkipNext: false,
      canSkipPrevious: false,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
    );
  }

  void bindControlCallbacks({
    Future<void> Function()? onPlayRequested,
    Future<void> Function()? onPauseRequested,
    Future<void> Function()? onStopRequested,
    Future<void> Function()? onSkipToNextRequested,
    Future<void> Function()? onSkipToPreviousRequested,
    Future<void> Function(Duration position)? onSeekRequested,
  }) {
    _onPlayRequested = onPlayRequested;
    _onPauseRequested = onPauseRequested;
    _onStopRequested = onStopRequested;
    _onSkipToNextRequested = onSkipToNextRequested;
    _onSkipToPreviousRequested = onSkipToPreviousRequested;
    _onSeekRequested = onSeekRequested;
  }

  Future<void> updateNowPlaying({
    required Song song,
    required bool isPlaying,
    required bool isLoading,
    required bool isCompleted,
    required bool canSkipNext,
    required bool canSkipPrevious,
    required Duration position,
    required Duration bufferedPosition,
    Duration? duration,
  }) async {
    if (!_initialized) {
      return;
    }

    final item = _songToMediaItem(song, duration: duration);
    if (mediaItem.value?.id != item.id ||
        mediaItem.value?.title != item.title ||
        mediaItem.value?.artist != item.artist ||
        mediaItem.value?.duration != item.duration) {
      mediaItem.add(item);
      await _persistLastSong(song, duration: duration);
    }

    _pushPlaybackState(
      isPlaying: isPlaying,
      isLoading: isLoading,
      isCompleted: isCompleted,
      canSkipNext: canSkipNext,
      canSkipPrevious: canSkipPrevious,
      position: position,
      bufferedPosition: bufferedPosition,
    );
  }

  Future<void> clearNowPlaying() async {
    if (!_initialized) {
      return;
    }

    mediaItem.add(null);
    _pushPlaybackState(
      isPlaying: false,
      isLoading: false,
      isCompleted: false,
      canSkipNext: false,
      canSkipPrevious: false,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
    );
  }

  @override
  Future<void> play() async {
    final callback = _onPlayRequested;
    if (callback != null) {
      await callback();
    }
  }

  @override
  Future<void> pause() async {
    final callback = _onPauseRequested;
    if (callback != null) {
      await callback();
    }
  }

  @override
  Future<void> stop() async {
    final callback = _onStopRequested;
    if (callback != null) {
      await callback();
    }
  }

  @override
  Future<void> skipToNext() async {
    final callback = _onSkipToNextRequested;
    if (callback != null) {
      await callback();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final callback = _onSkipToPreviousRequested;
    if (callback != null) {
      await callback();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final callback = _onSeekRequested;
    if (callback != null) {
      await callback(position);
    }
  }

  MediaItem _songToMediaItem(Song song, {Duration? duration}) {
    final songId = song.id.trim();
    final id = songId.isNotEmpty
        ? songId
        : '${song.title.trim().toLowerCase()}-${(song.artist ?? '').trim().toLowerCase()}';

    final artwork = (song.coverUrl ?? '').trim();
    final safeArtist = (song.artist ?? '').trim();

    return MediaItem(
      id: id,
      title: song.title,
      artist: safeArtist.isEmpty ? 'Unknown Artist' : safeArtist,
      album: (song.albumName ?? '').trim().isEmpty ? null : song.albumName,
      artUri: artwork.isEmpty ? null : Uri.tryParse(artwork),
      duration: duration ??
          (song.duration != null && song.duration! > 0
              ? Duration(seconds: song.duration!)
              : null),
      extras: {
        'cover_url': artwork,
        'song_id': song.id,
      },
    );
  }

  void _pushPlaybackState({
    required bool isPlaying,
    required bool isLoading,
    required bool isCompleted,
    required bool canSkipNext,
    required bool canSkipPrevious,
    required Duration position,
    required Duration bufferedPosition,
  }) {
    final controls = <MediaControl>[
      if (canSkipPrevious) MediaControl.skipToPrevious,
      isPlaying ? MediaControl.pause : MediaControl.play,
      if (canSkipNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];

    final compact = <int>[];
    final playPauseIndex = controls.indexWhere(
      (control) =>
          control == MediaControl.play || control == MediaControl.pause,
    );
    if (playPauseIndex >= 0) {
      compact.add(playPauseIndex);
    }
    final prevIndex = controls.indexOf(MediaControl.skipToPrevious);
    if (prevIndex >= 0 && compact.length < 3) {
      compact.add(prevIndex);
    }
    final nextIndex = controls.indexOf(MediaControl.skipToNext);
    if (nextIndex >= 0 && compact.length < 3) {
      compact.add(nextIndex);
    }

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.stop,
        },
        androidCompactActionIndices: compact,
        processingState: _processingState(
          isLoading: isLoading,
          isCompleted: isCompleted,
        ),
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: 1.0,
      ),
    );
  }

  AudioProcessingState _processingState({
    required bool isLoading,
    required bool isCompleted,
  }) {
    if (isLoading) {
      return AudioProcessingState.loading;
    }
    if (isCompleted) {
      return AudioProcessingState.completed;
    }
    return AudioProcessingState.ready;
  }

  Future<void> _persistLastSong(Song song, {Duration? duration}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastSongKey,
        jsonEncode({
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'cover_url': song.coverUrl,
          'album_name': song.albumName,
          'duration_seconds': duration?.inSeconds ?? song.duration,
        }),
      );
    } catch (_) {
      // Keep playback resilient even if local persistence fails.
    }
  }

  Future<void> _restoreLastSongForSessionContinuity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastSongKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }

      final data = Map<String, dynamic>.from(decoded);
      final title = (data['title'] ?? '').toString().trim();
      if (title.isEmpty) {
        return;
      }

      final song = Song(
        id: (data['id'] ?? '').toString(),
        title: title,
        artist: data['artist']?.toString(),
        albumName: data['album_name']?.toString(),
        coverUrl: data['cover_url']?.toString(),
        duration: int.tryParse((data['duration_seconds'] ?? '').toString()),
      );

      final durationSeconds =
          int.tryParse((data['duration_seconds'] ?? '').toString()) ?? 0;
      final restoredDuration = durationSeconds > 0
          ? Duration(seconds: durationSeconds)
          : null;

      mediaItem.add(_songToMediaItem(song, duration: restoredDuration));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Notification restore skipped: $e');
      }
    }
  }
}
